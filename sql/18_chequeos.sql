-- Daily data-quality assertions (scheduled query at 07:00 UTC, after the 06:00 refresh, as sa-transform).
-- A failed ASSERT fails the run, and the failure email of the scheduled query alerts the team.
-- Cost: COUNT(*) without filters is answered from table metadata; the rest reads small tables.

-- 1. Dead-letter growth: more than 1 000 rejected messages in 24 h means a broken producer or schema change
ASSERT (
  SELECT COUNT(*) FROM ecommerce.events_deadletter
  WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)) <= 1000
AS 'Dead-letter: más de 1 000 mensajes rechazados en 24 h (revisar events_deadletter)';

-- 2. Dashboards consistent with the raw layer (every event is counted once in agg_pedidos_hora)
ASSERT (SELECT SUM(eventos) FROM ecommerce.agg_pedidos_hora) = (SELECT COUNT(*) FROM ecommerce.events_raw)
AS 'agg_pedidos_hora no cuadra con events_raw (falló el refresco incremental)';

-- 3. Curated funnel without null keys or negative values
ASSERT NOT EXISTS (
  SELECT 1 FROM ecommerce.agg_embudo_categoria_dia
  WHERE fecha IS NULL OR categoria_comun IS NULL OR sesiones_view < 0 OR ingresos < 0)
AS 'agg_embudo_categoria_dia con claves nulas o valores negativos';

-- 4. Streaming path deduplicated (no identical stream events in the last refreshed days)
ASSERT (
  SELECT COUNT(*) - COUNT(DISTINCT TO_JSON_STRING(STRUCT(event_time, event_type, product_id, category_id,
                                                         category_code, brand, price, user_session)))
  FROM ecommerce.events_raw
  WHERE source = 'stream' AND ingest_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 48 HOUR)) = 0
AS 'Hay eventos duplicados del streaming sin deduplicar';

-- 5. Taxonomy break: a category whose last-7-day average moves more than 4x against the previous 28 days
--    (the December file relabelled smartphones as construction: x50). Peaks such as 15-17 Nov stay below 2x.
ASSERT NOT EXISTS (
  WITH d AS (
    SELECT fecha, categoria_comun, SUM(compras) AS compras FROM ecommerce.agg_embudo_categoria_dia GROUP BY 1, 2),
  ref AS (SELECT MAX(fecha) AS fin FROM d),
  v AS (
    SELECT categoria_comun,
      AVG(IF(fecha > fin - 7, compras, NULL)) AS ult7,
      AVG(IF(fecha BETWEEN fin - 34 AND fin - 7, compras, NULL)) AS prev28
    FROM d, ref GROUP BY categoria_comun)
  SELECT 1 FROM v
  WHERE prev28 >= 50 AND (ult7 > 4 * prev28 OR ult7 < prev28 / 4))
AS 'Salto de más de 4x en una categoría: posible cambio de taxonomía en el origen (ver dim_producto)';

-- 6. Purchases without category stay near their 24 % baseline (products missing from dim_producto)
ASSERT (
  SELECT SAFE_DIVIDE(SUM(IF(categoria_comun = 'sin_categoria', compras, 0)), SUM(compras))
  FROM ecommerce.agg_embudo_categoria_dia
  WHERE fecha > (SELECT MAX(fecha) - 7 FROM ecommerce.agg_embudo_categoria_dia)) <= 0.35
AS 'Más de 35 % de compras sin categoría en los últimos 7 días (productos nuevos sin mapear)';
