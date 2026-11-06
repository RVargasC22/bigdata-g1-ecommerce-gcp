-- fact_eventos: view over events_raw (no data copy); date filters still prune partitions.
-- The category comes from dim_producto (stable per product), not from the event: the December file
-- carries an inconsistent category_code (see sql/03_dims.sql). The raw code stays in category_code.
CREATE OR REPLACE VIEW ecommerce.fact_eventos AS
SELECT
  e.*,
  DATE(e.event_time) AS fecha,
  EXTRACT(HOUR FROM e.event_time) AS hora,
  EXTRACT(DAYOFWEEK FROM e.event_time) AS dia_semana_num,
  p.categoria_rees46,
  p.categoria_comun
FROM ecommerce.events_raw e
LEFT JOIN ecommerce.dim_producto p USING (product_id);

-- fact_pedidos: Olist, grain = order x category. Olist times are Sao Paulo local -> UTC.
CREATE OR REPLACE TABLE ecommerce.fact_pedidos
PARTITION BY DATE_TRUNC(fecha_compra, MONTH)
CLUSTER BY categoria_comun AS
WITH items AS (
  SELECT
    i.order_id,
    t.product_category_name_english AS categoria_olist,
    COUNT(*) AS items,
    SUM(i.price) AS valor_items,
    SUM(i.freight_value) AS valor_flete
  FROM ecommerce.olist_order_items i
  JOIN ecommerce.olist_products p USING (product_id)
  LEFT JOIN ecommerce.olist_category_translation t
    ON t.product_category_name = p.product_category_name
  GROUP BY 1, 2
),
pagos AS (
  SELECT order_id, ARRAY_AGG(payment_type ORDER BY payment_value DESC LIMIT 1)[OFFSET(0)] AS payment_type
  FROM ecommerce.olist_order_payments
  GROUP BY order_id
),
o AS (
  SELECT
    order_id,
    order_status,
    TIMESTAMP(DATETIME(order_purchase_timestamp), 'America/Sao_Paulo') AS compra_utc,
    TIMESTAMP(DATETIME(order_delivered_carrier_date), 'America/Sao_Paulo') AS despacho_utc,
    TIMESTAMP(DATETIME(order_delivered_customer_date), 'America/Sao_Paulo') AS entrega_utc,
    DATE(order_estimated_delivery_date) AS entrega_estimada
  FROM ecommerce.olist_orders
)
SELECT
  o.order_id,
  o.order_status,
  o.compra_utc,
  DATE(o.compra_utc) AS fecha_compra,
  EXTRACT(HOUR FROM o.compra_utc) AS hora,
  EXTRACT(DAYOFWEEK FROM o.compra_utc) AS dia_semana_num,
  it.categoria_olist,
  c.categoria_comun,
  it.items,
  it.valor_items,
  it.valor_flete,
  pg.payment_type,
  TIMESTAMP_DIFF(o.despacho_utc, o.compra_utc, HOUR) / 24 AS dias_a_despacho,
  TIMESTAMP_DIFF(o.entrega_utc, o.compra_utc, HOUR) / 24 AS dias_entrega,
  DATE_DIFF(DATE(o.entrega_utc), o.entrega_estimada, DAY) AS dias_vs_estimado   -- > 0 = atrasado
FROM o
JOIN items it USING (order_id)
LEFT JOIN pagos pg USING (order_id)
LEFT JOIN ecommerce.dim_categoria c
  ON c.fuente = 'olist' AND c.categoria_fuente = it.categoria_olist;
