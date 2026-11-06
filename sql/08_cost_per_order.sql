-- Section 3: cost per order = (C_storage + C_consultas + C_pubsub + C_dataflow + C_otros) / N
-- N and the BigQuery terms come from here; Pub/Sub and Dataflow come from the billing report
-- (Billing > Reports, filter label componente=pubsub / componente=dataflow) -> set them below.
-- Values below: demo run of 2026-11-05 at list prices (check against the billing report).
DECLARE c_pubsub_usd   NUMERIC DEFAULT 0;     -- ~7 GB, inside the 10 GiB monthly free tier
DECLARE c_dataflow_usd NUMERIC DEFAULT 1.05;  -- job metrics: 8.9 vCPU-h, 33 GB-h RAM, 3.46 SECU-h
DECLARE c_storage_gcs_usd NUMERIC DEFAULT 0.19; -- 7.2 GB Standard multi-region US, per month

WITH n AS (
  SELECT COUNT(DISTINCT user_session) AS pedidos
  FROM ecommerce.events_raw
  WHERE event_type = 'purchase'
),
consultas AS (
  -- on-demand price ~6.25 USD/TiB (first TiB/month free, ignored here to show the full cost)
  SELECT
    SUM(total_bytes_billed) / POW(1024, 4) AS tib_facturados,
    SUM(total_bytes_billed) / POW(1024, 4) * 6.25 AS usd_consultas
  FROM `region-us`.INFORMATION_SCHEMA.JOBS
  WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND job_type = 'QUERY' AND state = 'DONE'
),
almacenamiento AS (
  -- __TABLES__ instead of INFORMATION_SCHEMA.TABLE_STORAGE (access denied for this account).
  -- Every table is < 90 days old, so all of it is billed as active storage.
  SELECT
    SUM(size_bytes) / POW(1024, 3) AS gb_activos,
    0 AS gb_largo_plazo,
    SUM(size_bytes) / POW(1024, 3) * 0.02 AS usd_bq_storage_mes
  FROM ecommerce.__TABLES__
)
SELECT
  n.pedidos,
  a.gb_activos, a.gb_largo_plazo, a.usd_bq_storage_mes,
  c.tib_facturados, c.usd_consultas,
  c_pubsub_usd AS usd_pubsub, c_dataflow_usd AS usd_dataflow, c_storage_gcs_usd AS usd_gcs,
  a.usd_bq_storage_mes + c.usd_consultas + c_pubsub_usd + c_dataflow_usd + c_storage_gcs_usd AS usd_total,
  SAFE_DIVIDE(a.usd_bq_storage_mes + c.usd_consultas + c_pubsub_usd + c_dataflow_usd + c_storage_gcs_usd,
              n.pedidos) AS usd_por_pedido,
  SAFE_DIVIDE(a.usd_bq_storage_mes + c.usd_consultas + c_pubsub_usd + c_dataflow_usd + c_storage_gcs_usd,
              n.pedidos) * 1000 AS usd_por_1000_pedidos
FROM n, consultas c, almacenamiento a;

-- Query cost by script label (which step costs what)
SELECT
  (SELECT value FROM UNNEST(labels) WHERE key = 'script') AS script,
  COUNT(*) AS jobs,
  ROUND(SUM(total_bytes_billed) / POW(1024, 3), 2) AS gb_facturados
FROM `region-us`.INFORMATION_SCHEMA.JOBS
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND job_type = 'QUERY'
GROUP BY script
ORDER BY gb_facturados DESC;
