-- Small aggregated tables that feed Looker Studio (dashboards never scan events_raw).
-- Pedido = user_session with at least one purchase.

CREATE OR REPLACE TABLE ecommerce.agg_pedidos_hora AS
SELECT
  TIMESTAMP_TRUNC(event_time, HOUR) AS hora,
  COUNT(DISTINCT IF(event_type = 'purchase', user_session, NULL)) AS pedidos,
  COUNTIF(event_type = 'purchase') AS compras,
  SUM(IF(event_type = 'purchase', price, 0)) AS ingresos,
  COUNT(*) AS eventos
FROM ecommerce.events_raw
GROUP BY hora;

CREATE OR REPLACE TABLE ecommerce.agg_embudo_categoria_dia AS
SELECT
  fecha,
  COALESCE(categoria_comun, 'sin_categoria') AS categoria_comun,  -- REES46 products without category_code
  categoria_rees46,
  COUNT(DISTINCT IF(event_type = 'view', user_session, NULL)) AS sesiones_view,
  COUNT(DISTINCT IF(event_type = 'cart', user_session, NULL)) AS sesiones_cart,
  COUNT(DISTINCT IF(event_type = 'purchase', user_session, NULL)) AS sesiones_purchase,
  COUNTIF(event_type = 'purchase') AS compras,
  SUM(IF(event_type = 'purchase', price, 0)) AS ingresos
FROM ecommerce.fact_eventos
GROUP BY fecha, 2, categoria_rees46;

CREATE OR REPLACE TABLE ecommerce.agg_entregas_categoria AS
SELECT
  categoria_comun,
  categoria_olist,
  COUNT(DISTINCT order_id) AS pedidos,
  AVG(dias_entrega) AS dias_entrega_prom,
  APPROX_QUANTILES(dias_entrega, 100)[OFFSET(50)] AS dias_entrega_p50,
  AVG(dias_vs_estimado) AS dias_vs_estimado_prom,
  COUNTIF(dias_vs_estimado > 0) / COUNTIF(dias_vs_estimado IS NOT NULL) AS pct_atrasados,
  AVG(valor_flete) AS flete_prom
FROM ecommerce.fact_pedidos
WHERE order_status = 'delivered'
GROUP BY categoria_comun, categoria_olist;

-- Cross 1: demand vs derived inventory, per day
CREATE OR REPLACE TABLE ecommerce.agg_demanda_vs_inventario AS
SELECT
  i.fecha,
  f.evento,
  SUM(i.unidades_vendidas) AS unidades_vendidas,
  COUNT(DISTINCT i.product_id) AS productos_vendidos,
  COUNT(DISTINCT IF(i.quiebre, i.product_id, NULL)) AS productos_en_quiebre,
  SUM(i.demanda_no_atendida) AS demanda_no_atendida
FROM ecommerce.fact_inventario i
LEFT JOIN ecommerce.dim_fecha f USING (fecha)
GROUP BY i.fecha, f.evento;

-- Cross 2: REES46 conversion vs Olist fulfilment, by common category
CREATE OR REPLACE TABLE ecommerce.agg_conversion_vs_cumplimiento AS
WITH conv AS (
  SELECT
    categoria_comun,
    SUM(sesiones_view) AS sesiones_view,
    SUM(sesiones_cart) AS sesiones_cart,
    SUM(sesiones_purchase) AS sesiones_purchase
  FROM ecommerce.agg_embudo_categoria_dia
  WHERE categoria_comun != 'sin_categoria'
  GROUP BY categoria_comun
),
cump AS (
  SELECT
    categoria_comun,
    SUM(pedidos) AS pedidos_olist,
    SUM(dias_entrega_prom * pedidos) / SUM(pedidos) AS dias_entrega_prom,
    SUM(dias_vs_estimado_prom * pedidos) / SUM(pedidos) AS dias_vs_estimado_prom,
    SUM(pct_atrasados * pedidos) / SUM(pedidos) AS pct_atrasados
  FROM ecommerce.agg_entregas_categoria
  WHERE categoria_comun IS NOT NULL
  GROUP BY categoria_comun
)
SELECT
  categoria_comun,
  conv.sesiones_view,
  conv.sesiones_purchase,
  SAFE_DIVIDE(conv.sesiones_cart, conv.sesiones_view) AS tasa_view_cart,
  SAFE_DIVIDE(conv.sesiones_purchase, conv.sesiones_view) AS tasa_conversion,
  cump.pedidos_olist,
  cump.dias_entrega_prom,
  cump.dias_vs_estimado_prom,
  cump.pct_atrasados
FROM conv FULL JOIN cump USING (categoria_comun);

-- Cross 3: hour-of-day x weekday pattern for both stores (they share no calendar period)
CREATE OR REPLACE TABLE ecommerce.agg_patron_horario AS
SELECT 'rees46' AS fuente, dia_semana_num, hora,
       COUNT(DISTINCT IF(event_type = 'purchase', user_session, NULL)) AS pedidos
FROM ecommerce.fact_eventos
GROUP BY dia_semana_num, hora
UNION ALL
SELECT 'olist', dia_semana_num, hora, COUNT(DISTINCT order_id)
FROM ecommerce.fact_pedidos
GROUP BY dia_semana_num, hora;

-- Near-real-time view for the stream: incrementally maintained, includes the streaming buffer.
CREATE MATERIALIZED VIEW IF NOT EXISTS ecommerce.mv_eventos_hora
OPTIONS (enable_refresh = true, refresh_interval_minutes = 5) AS
SELECT
  TIMESTAMP_TRUNC(event_time, HOUR) AS hora,
  event_type,
  source,
  COUNT(*) AS eventos,
  SUM(price) AS monto
FROM ecommerce.events_raw
GROUP BY hora, event_type, source;
