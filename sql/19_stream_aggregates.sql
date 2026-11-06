-- Gold table written in real time by the Beam pipeline (streaming/beam/pipeline.py): events per event minute
-- and common category, enriched with dim_producto inside the stream. Each event is counted in exactly one row;
-- a (minuto, categoria_comun) can have several rows (a replay spreads one minute over several arrival windows,
-- late events add a row), so readers SUM them.
CREATE TABLE IF NOT EXISTS ecommerce.stream_categoria_minuto (
  minuto TIMESTAMP NOT NULL OPTIONS (description = 'Minuto del evento (event_time truncado, UTC).'),
  ventana TIMESTAMP OPTIONS (description = 'Inicio de la ventana de 1 minuto en que llegaron los eventos (hora de publicación en Pub/Sub).'),
  categoria_comun STRING NOT NULL OPTIONS (description = 'Categoría común del producto según dim_producto; sin_categoria si el producto no existe.'),
  eventos INT64 OPTIONS (description = 'Eventos válidos de la ventana.'),
  vistas INT64,
  carritos INT64,
  remociones INT64,
  compras INT64,
  ingresos FLOAT64 OPTIONS (description = 'Suma de price de los eventos purchase.'),
  disparo STRING OPTIONS (description = 'a_tiempo: la ventana cerró con el watermark; tardio: eventos que llegaron después del cierre (hasta 10 min), en una fila aparte.'),
  procesado_en TIMESTAMP OPTIONS (description = 'Hora real en que Dataflow cerró la ventana y escribió la fila.')
)
PARTITION BY DATE(minuto)
CLUSTER BY categoria_comun
OPTIONS (labels = [('capa', 'gold'), ('fuente', 'rees46')],
         description = 'Agregado en tiempo real (Apache Beam en Dataflow): eventos por minuto y categoría común.');

-- Reconciliation: stream result vs the same aggregation done in batch over fact_eventos, for a time range.
-- The parameters filter event_time, so only the partitions of that range are scanned.
-- Use: SELECT * FROM ecommerce.conciliar_stream('2019-11-17 10:00:00', '2019-11-17 10:30:00') WHERE NOT coincide
CREATE OR REPLACE TABLE FUNCTION ecommerce.conciliar_stream(desde TIMESTAMP, hasta TIMESTAMP)
OPTIONS (description = 'Compara stream_categoria_minuto con el mismo agregado calculado en batch sobre fact_eventos.')
AS
WITH stream AS (
  SELECT minuto, categoria_comun, SUM(eventos) AS eventos, SUM(compras) AS compras,
    ROUND(SUM(ingresos), 2) AS ingresos
  FROM ecommerce.stream_categoria_minuto
  WHERE minuto >= desde AND minuto < hasta
  GROUP BY 1, 2
),
batch AS (
  SELECT TIMESTAMP_TRUNC(event_time, MINUTE) AS minuto, IFNULL(categoria_comun, 'sin_categoria') AS categoria_comun,
    COUNT(*) AS eventos, COUNTIF(event_type = 'purchase') AS compras,
    ROUND(SUM(IF(event_type = 'purchase', IFNULL(price, 0), 0)), 2) AS ingresos
  FROM ecommerce.fact_eventos
  WHERE event_time >= desde AND event_time < hasta
  GROUP BY 1, 2
)
SELECT minuto, categoria_comun,
  s.eventos AS eventos_stream, b.eventos AS eventos_batch,
  s.compras AS compras_stream, b.compras AS compras_batch,
  s.ingresos AS ingresos_stream, b.ingresos AS ingresos_batch,
  IFNULL(s.eventos = b.eventos AND s.compras = b.compras AND ABS(s.ingresos - b.ingresos) < 0.01, FALSE) AS coincide
FROM stream s
FULL JOIN batch b USING (minuto, categoria_comun);
