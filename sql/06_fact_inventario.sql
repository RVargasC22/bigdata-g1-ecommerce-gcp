-- fact_inventario: derived stock. Rule: each product starts every week (Monday) with stock_inicial
-- units; each purchase takes one unit; weekly restock back to stock_inicial.
CREATE OR REPLACE TABLE ecommerce.fact_inventario
PARTITION BY fecha
CLUSTER BY product_id AS
WITH params AS (SELECT 50 AS stock_inicial),
ventas AS (
  SELECT product_id, DATE(event_time) AS fecha, COUNT(*) AS unidades_vendidas
  FROM ecommerce.events_raw
  WHERE event_type = 'purchase' AND product_id IS NOT NULL
  GROUP BY 1, 2
),
acum AS (
  SELECT
    v.*,
    DATE_TRUNC(fecha, WEEK(MONDAY)) AS semana,
    SUM(unidades_vendidas) OVER (
      PARTITION BY product_id, DATE_TRUNC(fecha, WEEK(MONDAY)) ORDER BY fecha) AS vendidas_semana
  FROM ventas v
)
SELECT
  a.product_id,
  a.fecha,
  a.semana,
  a.unidades_vendidas,
  p.stock_inicial AS stock_inicio_semana,
  GREATEST(p.stock_inicial - a.vendidas_semana, 0) AS stock_fin_dia,
  a.vendidas_semana >= p.stock_inicial AS quiebre,
  GREATEST(a.vendidas_semana - p.stock_inicial, 0)
    - GREATEST(a.vendidas_semana - a.unidades_vendidas - p.stock_inicial, 0) AS demanda_no_atendida
FROM acum a CROSS JOIN params p;
