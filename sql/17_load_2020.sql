-- Incremental batch load of REES46 2020 months (ingest/fetch_2020.sh -> GCS -> events_staging_2020).
-- Same parsing and exact-duplicate removal as sql/02_load_events.sql. Replaces only the months present in the
-- staging table, so loading April alone keeps January-March; idempotent.
-- A full reload (ingest/bq_load.sh) also picks these files up, since it loads raw/rees46/*.csv.gz.
DECLARE meses ARRAY<DATE> DEFAULT (
  SELECT ARRAY_AGG(DISTINCT DATE_TRUNC(DATE(SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S UTC', event_time)), MONTH))
  FROM ecommerce.events_staging_2020
  WHERE SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S UTC', event_time) >= '2020-01-01');

BEGIN TRANSACTION;
DELETE FROM ecommerce.events_raw
WHERE source = 'batch' AND event_time >= '2020-01-01' AND DATE_TRUNC(DATE(event_time), MONTH) IN UNNEST(meses);

INSERT INTO ecommerce.events_raw
  (event_time, event_type, product_id, category_id, category_code, brand, price,
   user_id, user_session, source, ingest_time)
SELECT DISTINCT
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S UTC', event_time),
  event_type,
  SAFE_CAST(product_id AS INT64),
  SAFE_CAST(category_id AS INT64),
  NULLIF(category_code, ''),
  NULLIF(brand, ''),
  SAFE_CAST(price AS NUMERIC),
  SAFE_CAST(user_id AS INT64),
  NULLIF(user_session, ''),
  'batch',
  CURRENT_TIMESTAMP()
FROM ecommerce.events_staging_2020
WHERE event_type IN ('view', 'cart', 'remove_from_cart', 'purchase')
  AND SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S UTC', event_time) >= '2020-01-01';
COMMIT TRANSACTION;

SELECT FORMAT_DATE('%Y-%m', DATE(event_time)) AS mes, COUNT(*) AS eventos, COUNTIF(event_type = 'purchase') AS compras
FROM ecommerce.events_raw WHERE event_time >= '2020-01-01' GROUP BY mes ORDER BY mes;

DROP TABLE ecommerce.events_staging_2020;
