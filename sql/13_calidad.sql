-- Data quality report.
SELECT 'eventos por fuente' AS chequeo, source AS detalle, COUNT(*) AS filas
FROM ecommerce.events_raw GROUP BY source
UNION ALL
SELECT 'categorias rees46 sin pareja', categoria_rees46, COUNT(*)
FROM ecommerce.dim_producto WHERE categoria_comun IS NULL GROUP BY categoria_rees46
UNION ALL
-- December file: raw category_code that contradicts the product's Oct-Nov category (dim_producto)
SELECT 'compras con category_code distinto al del producto', FORMAT_DATE('%Y-%m', DATE(e.event_time)), COUNT(*)
FROM ecommerce.events_raw e JOIN ecommerce.dim_producto p USING (product_id)
WHERE e.event_type = 'purchase' AND e.category_code IS DISTINCT FROM p.category_code AND p.category_code IS NOT NULL
GROUP BY 2
UNION ALL
SELECT 'categorias olist sin pareja', IFNULL(categoria_olist, '(sin categoria)'), COUNT(DISTINCT order_id)
FROM ecommerce.fact_pedidos WHERE categoria_comun IS NULL GROUP BY categoria_olist
ORDER BY chequeo, filas DESC;
