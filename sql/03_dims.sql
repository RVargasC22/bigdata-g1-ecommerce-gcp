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
FROM UNNEST(GENERATE_DATE_ARRAY('2016-09-01', '2020-04-30')) AS d;

-- One category per product, taken from Oct-Nov 2019 (Kaggle files). The December file (data.rees46.com
-- mirror) uses a different category_id / category_code numbering: 76 % of December purchases carry a code
-- that contradicts the product's Oct-Nov code (e.g. Samsung smartphones as construction.tools.light).
-- Products first seen from December on (2.2 % of December purchases, 16 % of March, 22 % of April 2020) are
-- classified through a bridge: each new category_id takes the Oct-Nov top-level category that most of its
-- products (those present in both periods) had, if it has at least 5 such products and 80 % of them agree.
-- Measured on Dec 2019-Apr 2020: 977 new ids with >= 5 shared products, mean agreement 94 %, 862 pass 80 %.
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
    APPROX_QUANTILES(price, 2)[OFFSET(1)] AS precio_mediano,
    MIN(event_time) < '2019-12-01' AS visto_oct_nov
  FROM ecommerce.events_raw
  WHERE product_id IS NOT NULL
  GROUP BY product_id
),
cat_nueva AS (  -- most frequent category_id per product in the mirror numbering (Dec 2019 on)
  SELECT product_id, category_id AS category_id_nueva
  FROM ecommerce.events_raw
  WHERE product_id IS NOT NULL AND category_id IS NOT NULL AND DATE(event_time) >= '2019-12-01'
  GROUP BY product_id, category_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY COUNT(*) DESC, category_id) = 1
),
votos AS (  -- shared products vote with their Oct-Nov top-level category ('' = no category)
  SELECT n.category_id_nueva, IFNULL(SPLIT(r.category_code, '.')[SAFE_OFFSET(0)], '') AS cat, COUNT(*) AS n
  FROM cat_nueva n JOIN p USING (product_id) LEFT JOIN cat_ref r USING (product_id)
  WHERE p.visto_oct_nov
  GROUP BY 1, 2
),
puente AS (
  SELECT category_id_nueva, NULLIF(cat, '') AS categoria_rees46
  FROM (SELECT *, SUM(n) OVER (PARTITION BY category_id_nueva) AS total FROM votos)
  WHERE total >= 5 AND n / total >= 0.8
  QUALIFY ROW_NUMBER() OVER (PARTITION BY category_id_nueva ORDER BY n DESC) = 1
),
cat AS (
  SELECT p.*, r.category_id, r.category_code,
    IF(p.visto_oct_nov, SPLIT(r.category_code, '.')[SAFE_OFFSET(0)], b.categoria_rees46) AS categoria_rees46,
    CASE WHEN p.visto_oct_nov THEN 'oct-nov' WHEN b.category_id_nueva IS NOT NULL THEN 'puente' END AS origen_categoria
  FROM p
  LEFT JOIN cat_ref r USING (product_id)
  LEFT JOIN cat_nueva n USING (product_id)
  LEFT JOIN puente b USING (category_id_nueva)
)
SELECT
  product_id, category_id, category_code, categoria_rees46, brand, precio_mediano, origen_categoria,
  c.categoria_comun
FROM cat
LEFT JOIN ecommerce.dim_categoria c ON c.fuente = 'rees46' AND c.categoria_fuente = cat.categoria_rees46;
