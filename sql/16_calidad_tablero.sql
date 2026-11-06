-- Tables for the "Calidad y gobierno" dashboard page.

-- Reconciliation per replayed day. publicados / fallos come from the producer log (docs/evidencia/replays.log);
-- cargados_dataflow and duplicados_origen were measured in events_raw on 2026-11-05, before the stream
-- deduplication step (sql/17_incremental.sql) removed the duplicates.
--   diferencia        = cargados_dataflow - publicados: 0 = nothing lost; > 0 = Pub/Sub at-least-once redelivery
--   duplicados_origen = rows repeated inside the source CSV itself (also removed in the batch path)
--   filas_finales     = rows in events_raw today, after deduplication
CREATE OR REPLACE TABLE ecommerce.agg_conciliacion_stream
OPTIONS (labels = [('capa', 'gold')],
         description = 'Conciliación por replay: publicados en Pub/Sub vs cargados por Dataflow (cero pérdida) y filas finales tras deduplicar.')
AS
WITH medido AS (
  SELECT * FROM UNNEST([
    STRUCT(DATE '2019-11-17' AS dia, 'Pico 17/11 (10x)' AS replay, 6395377 AS publicados,
           0 AS fallos_publicacion, 6395377 AS cargados_dataflow, 15456 AS duplicados_origen),
    STRUCT(DATE '2019-11-29', 'Black Friday (60x)', 1854426, 0, 1854430, 3606),
    STRUCT(DATE '2019-12-02', 'Cyber Monday (60x)', 1741047, 0, 1741047, 2634)])
),
hoy AS (
  SELECT DATE(event_time) AS dia, COUNT(*) AS filas_finales
  FROM ecommerce.events_raw
  WHERE source = 'stream' AND DATE(event_time) IN ('2019-11-17', '2019-11-29', '2019-12-02')
  GROUP BY dia
)
SELECT
  m.dia, m.replay, m.publicados, m.fallos_publicacion, m.cargados_dataflow AS cargados,
  m.cargados_dataflow - m.publicados AS diferencia,
  SAFE_DIVIDE(m.cargados_dataflow, m.publicados) AS pct_entregado,
  m.duplicados_origen,
  h.filas_finales
FROM medido m LEFT JOIN hoy h USING (dia);

-- Dead-letter rejections grouped by cause
CREATE OR REPLACE TABLE ecommerce.agg_calidad_deadletter
OPTIONS (labels = [('capa', 'gold')],
         description = 'Mensajes rechazados por la UDF de Dataflow (dead-letter) agrupados por causa; se refresca a diario (sql/17).')
AS
SELECT
  CASE
    WHEN errorMessage LIKE '%Invalid JSON%' OR errorMessage LIKE '%SyntaxError%' THEN 'JSON malformado'
    WHEN errorMessage LIKE 'invalid event_type%' THEN 'event_type desconocido'
    WHEN errorMessage LIKE 'invalid event_time%' THEN 'event_time inválido'
    WHEN errorMessage LIKE 'invalid price%' THEN 'precio inválido'
    WHEN errorMessage LIKE 'invalid %_id%' THEN 'ID no numérico'
    ELSE 'otro'
  END AS causa,
  COUNT(*) AS rechazos,
  MAX(timestamp) AS ultimo_rechazo
FROM ecommerce.events_deadletter
GROUP BY causa;

-- Pipeline metrics exported from Cloud Monitoring during the peak replay (monitoring/export_metrics.py)
ALTER TABLE ecommerce.ops_metricas_pipeline SET OPTIONS (labels = [('capa', 'gold')],
  description = 'Métricas por minuto del replay pico 17/11: vCPUs de Dataflow, system lag, antigüedad del watermark, backlog y tasa de publicación.');
