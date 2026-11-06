CREATE OR REPLACE TABLE ecommerce.dim_fecha AS
SELECT
  d AS fecha,
  EXTRACT(YEAR FROM d) AS anio,
  EXTRACT(MONTH FROM d) AS mes,
  EXTRACT(DAYOFWEEK FROM d) AS dia_semana_num,      -- 1 = domingo
  FORMAT_DATE('%A', d) AS dia_semana,
  EXTRACT(DAYOFWEEK FROM d) IN (1, 7) AS fin_de_semana,
  CASE d
    WHEN '2017-11-24' THEN 'Black Friday'
    WHEN '2018-11-23' THEN 'Black Friday'
    WHEN '2019-11-29' THEN 'Black Friday'
    WHEN '2019-12-02' THEN 'Cyber Monday'
  END AS evento
FROM UNNEST(GENERATE_DATE_ARRAY('2016-09-01', '2020-03-31')) AS d;

-- One category per product, taken from Oct-Nov 2019 (Kaggle files). The December file (data.rees46.com
-- mirror) uses a different category_id / category_code numbering: 76 % of December purchases carry a code
-- that contradicts the product's Oct-Nov code (e.g. Samsung smartphones as construction.tools.light).
-- Products first seen in December get no category (2.2 % of December purchases -> 'sin_categoria').
CREATE OR REPLACE TABLE ecommerce.dim_producto CLUSTER BY product_id AS
WITH cat_ref AS (  -- most frequent category per product in the reference months
  SELECT product_id, category_id, category_code
  FROM ecommerce.events_raw
  WHERE product_id IS NOT NULL AND category_code IS NOT NULL AND DATE(event_time) < '2019-12-01'
  GROUP BY product_id, category_id, category_code
  QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY COUNT(*) DESC, category_id) = 1
),
p AS (
  SELECT
    product_id,
    ANY_VALUE(brand) AS brand,
    APPROX_QUANTILES(price, 2)[OFFSET(1)] AS precio_mediano
  FROM ecommerce.events_raw
  WHERE product_id IS NOT NULL
  GROUP BY product_id
)
SELECT
  p.product_id, r.category_id, r.category_code,
  SPLIT(r.category_code, '.')[SAFE_OFFSET(0)] AS categoria_rees46,
  p.brand, p.precio_mediano,
  c.categoria_comun
FROM p
LEFT JOIN cat_ref r USING (product_id)
LEFT JOIN ecommerce.dim_categoria c
  ON c.fuente = 'rees46' AND c.categoria_fuente = SPLIT(r.category_code, '.')[SAFE_OFFSET(0)];
