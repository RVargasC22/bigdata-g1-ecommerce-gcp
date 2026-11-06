-- Staging -> events_raw: parse types, drop invalid rows, remove exact duplicates.
-- Days in stream_days are excluded: they arrive through Pub/Sub -> Dataflow (replay).
DECLARE stream_days ARRAY<DATE> DEFAULT [DATE '2019-11-17', DATE '2019-11-29', DATE '2019-12-02'];

DELETE FROM ecommerce.events_raw WHERE source = 'batch';

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
FROM ecommerce.events_staging
WHERE event_type IN ('view', 'cart', 'remove_from_cart', 'purchase')
  AND SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S UTC', event_time) IS NOT NULL
  AND DATE(SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S UTC', event_time)) NOT IN UNNEST(stream_days);

-- Load report: staged rows, rows kept, duplicates/invalid removed
SELECT
  (SELECT COUNT(*) FROM ecommerce.events_staging) AS filas_staging,
  (SELECT COUNT(*) FROM ecommerce.events_staging
    WHERE DATE(SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S UTC', event_time)) IN UNNEST(stream_days)) AS filas_dias_streaming,
  (SELECT COUNT(*) FROM ecommerce.events_raw WHERE source = 'batch') AS filas_cargadas;
