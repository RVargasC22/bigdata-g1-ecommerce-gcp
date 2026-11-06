-- Daily incremental refresh (scheduled query, runs as sa-transform). Replaces the full rebuild of
-- 05_analytics.sql / 06_fact_inventario.sql, which rescanned all of events_raw (~9 GB) every day.
-- Only the events_raw partitions modified in the last 26 h are processed (partition metadata is free to
-- read); with no new data the run scans almost nothing. Same logic as 05/06, restricted to those dates.
-- DML (DELETE + INSERT, TRUNCATE + INSERT) keeps table descriptions, labels and row access policies.
-- Initial / full loads still use 05_analytics.sql and 06_fact_inventario.sql (ingest/bq_load.sh).

DECLARE dias ARRAY<DATE> DEFAULT (
  SELECT IFNULL(ARRAY_AGG(PARSE_DATE('%Y%m%d', partition_id)), [])
  FROM ecommerce.INFORMATION_SCHEMA.PARTITIONS
  WHERE table_name = 'events_raw'
    AND partition_id NOT IN ('__NULL__', '__UNPARTITIONED__')  -- streaming buffer: next run
    AND last_modified_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 26 HOUR));
-- fact_inventario accumulates per week, so whole weeks touched by those dates are recomputed
DECLARE dias_semana ARRAY<DATE> DEFAULT (
  SELECT IFNULL(ARRAY_AGG(DISTINCT d), [])
  FROM UNNEST(dias) x,
       UNNEST(GENERATE_DATE_ARRAY(DATE_TRUNC(x, WEEK(MONDAY)),
                                  DATE_ADD(DATE_TRUNC(x, WEEK(MONDAY)), INTERVAL 6 DAY))) d);

SELECT ARRAY_LENGTH(dias) AS particiones_nuevas;

IF ARRAY_LENGTH(dias) > 0 THEN

  -- 1. Deduplicate the streaming path (the Dataflow template does not; the batch path uses SELECT DISTINCT).
  --    Keeps the first copy of each identical event; batch rows are never touched.
  CREATE TEMP TABLE stream_unico AS
  SELECT * EXCEPT (rn) FROM (
    SELECT *, ROW_NUMBER() OVER (
      PARTITION BY event_time, event_type, product_id, category_id, category_code, brand, price, user_id,
                   user_session
      ORDER BY ingest_time) AS rn
    FROM ecommerce.events_raw
    WHERE DATE(event_time) IN UNNEST(dias) AND source = 'stream')
  WHERE rn = 1;

  BEGIN TRANSACTION;
  DELETE FROM ecommerce.events_raw WHERE DATE(event_time) IN UNNEST(dias) AND source = 'stream';
  INSERT INTO ecommerce.events_raw SELECT * FROM stream_unico;
  COMMIT TRANSACTION;

  -- 2. agg_pedidos_hora
  DELETE FROM ecommerce.agg_pedidos_hora WHERE DATE(hora) IN UNNEST(dias);
  INSERT INTO ecommerce.agg_pedidos_hora
  SELECT
    TIMESTAMP_TRUNC(event_time, HOUR) AS hora,
    COUNT(DISTINCT IF(event_type = 'purchase', user_session, NULL)) AS pedidos,
    COUNTIF(event_type = 'purchase') AS compras,
    SUM(IF(event_type = 'purchase', price, 0)) AS ingresos,
    COUNT(*) AS eventos
  FROM ecommerce.events_raw
  WHERE DATE(event_time) IN UNNEST(dias)
  GROUP BY hora;

  -- 3. agg_embudo_categoria_dia
  DELETE FROM ecommerce.agg_embudo_categoria_dia WHERE fecha IN UNNEST(dias);
  INSERT INTO ecommerce.agg_embudo_categoria_dia
  SELECT
    fecha,
    COALESCE(categoria_comun, 'sin_categoria') AS categoria_comun,
    categoria_rees46,
    COUNT(DISTINCT IF(event_type = 'view', user_session, NULL)) AS sesiones_view,
    COUNT(DISTINCT IF(event_type = 'cart', user_session, NULL)) AS sesiones_cart,
    COUNT(DISTINCT IF(event_type = 'purchase', user_session, NULL)) AS sesiones_purchase,
    COUNTIF(event_type = 'purchase') AS compras,
    SUM(IF(event_type = 'purchase', price, 0)) AS ingresos
  FROM ecommerce.fact_eventos
  WHERE fecha IN UNNEST(dias)
  GROUP BY fecha, 2, categoria_rees46;

  -- 4. fact_inventario (whole weeks) and agg_demanda_vs_inventario
  DELETE FROM ecommerce.fact_inventario WHERE fecha IN UNNEST(dias_semana);
  INSERT INTO ecommerce.fact_inventario
  WITH params AS (SELECT 50 AS stock_inicial),
  ventas AS (
    SELECT product_id, DATE(event_time) AS fecha, COUNT(*) AS unidades_vendidas
    FROM ecommerce.events_raw
    WHERE event_type = 'purchase' AND product_id IS NOT NULL AND DATE(event_time) IN UNNEST(dias_semana)
    GROUP BY 1, 2
  ),
  acum AS (
    SELECT v.*, DATE_TRUNC(fecha, WEEK(MONDAY)) AS semana,
      SUM(unidades_vendidas) OVER (
        PARTITION BY product_id, DATE_TRUNC(fecha, WEEK(MONDAY)) ORDER BY fecha) AS vendidas_semana
    FROM ventas v
  )
  SELECT a.product_id, a.fecha, a.semana, a.unidades_vendidas,
    p.stock_inicial AS stock_inicio_semana,
    GREATEST(p.stock_inicial - a.vendidas_semana, 0) AS stock_fin_dia,
    a.vendidas_semana >= p.stock_inicial AS quiebre,
    GREATEST(a.vendidas_semana - p.stock_inicial, 0)
      - GREATEST(a.vendidas_semana - a.unidades_vendidas - p.stock_inicial, 0) AS demanda_no_atendida
  FROM acum a CROSS JOIN params p;

  DELETE FROM ecommerce.agg_demanda_vs_inventario WHERE fecha IN UNNEST(dias_semana);
  INSERT INTO ecommerce.agg_demanda_vs_inventario
  SELECT i.fecha, f.evento, SUM(i.unidades_vendidas), COUNT(DISTINCT i.product_id),
    COUNT(DISTINCT IF(i.quiebre, i.product_id, NULL)), SUM(i.demanda_no_atendida)
  FROM ecommerce.fact_inventario i
  LEFT JOIN ecommerce.dim_fecha f USING (fecha)
  WHERE i.fecha IN UNNEST(dias_semana)
  GROUP BY i.fecha, f.evento;

  -- 5. Small cross table, rebuilt from the aggregates (reads KB)
  TRUNCATE TABLE ecommerce.agg_conversion_vs_cumplimiento;
  INSERT INTO ecommerce.agg_conversion_vs_cumplimiento
  WITH conv AS (
    SELECT categoria_comun, SUM(sesiones_view) AS sesiones_view, SUM(sesiones_cart) AS sesiones_cart,
      SUM(sesiones_purchase) AS sesiones_purchase
    FROM ecommerce.agg_embudo_categoria_dia
    WHERE categoria_comun != 'sin_categoria'
    GROUP BY categoria_comun
  ),
  cump AS (
    SELECT categoria_comun, SUM(pedidos) AS pedidos_olist,
      SUM(dias_entrega_prom * pedidos) / SUM(pedidos) AS dias_entrega_prom,
      SUM(dias_vs_estimado_prom * pedidos) / SUM(pedidos) AS dias_vs_estimado_prom,
      SUM(pct_atrasados * pedidos) / SUM(pedidos) AS pct_atrasados
    FROM ecommerce.agg_entregas_categoria
    WHERE categoria_comun IS NOT NULL
    GROUP BY categoria_comun
  )
  SELECT categoria_comun, conv.sesiones_view, conv.sesiones_purchase,
    SAFE_DIVIDE(conv.sesiones_cart, conv.sesiones_view), SAFE_DIVIDE(conv.sesiones_purchase, conv.sesiones_view),
    cump.pedidos_olist, cump.dias_entrega_prom, cump.dias_vs_estimado_prom, cump.pct_atrasados
  FROM conv FULL JOIN cump USING (categoria_comun);

  -- agg_patron_horario counts distinct sessions over all dates (not additive by day): weekly full rebuild
  IF EXTRACT(DAYOFWEEK FROM CURRENT_DATE()) = 2 THEN
    TRUNCATE TABLE ecommerce.agg_patron_horario;
    INSERT INTO ecommerce.agg_patron_horario
    SELECT 'rees46', dia_semana_num, hora, COUNT(DISTINCT IF(event_type = 'purchase', user_session, NULL))
    FROM ecommerce.fact_eventos
    GROUP BY dia_semana_num, hora
    UNION ALL
    SELECT 'olist', dia_semana_num, hora, COUNT(DISTINCT order_id)
    FROM ecommerce.fact_pedidos
    GROUP BY dia_semana_num, hora;
  END IF;
END IF;

-- 6. Dead-letter summary for the dashboard (tiny table, every run)
TRUNCATE TABLE ecommerce.agg_calidad_deadletter;
INSERT INTO ecommerce.agg_calidad_deadletter
SELECT
  CASE
    WHEN errorMessage LIKE '%Invalid JSON%' OR errorMessage LIKE '%SyntaxError%' THEN 'JSON malformado'
    WHEN errorMessage LIKE 'invalid event_type%' THEN 'event_type desconocido'
    WHEN errorMessage LIKE 'invalid event_time%' THEN 'event_time inválido'
    WHEN errorMessage LIKE 'invalid price%' THEN 'precio inválido'
    WHEN errorMessage LIKE 'invalid %_id%' THEN 'ID no numérico'
    ELSE 'otro'
  END,
  COUNT(*), MAX(timestamp)
FROM ecommerce.events_deadletter
GROUP BY 1;
