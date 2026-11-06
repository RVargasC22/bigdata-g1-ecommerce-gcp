-- Controlled experiment on Olist: does more history, or a different model, beat a naive mean?
-- REES46 only has 3 months of training history (sql/16_forecast.sql) and ARIMA lost to the mean there.
-- Olist has 20 months (Jan 2017 - Aug 2018, one Black Friday), so the same test window is forecast by:
--   arima_17m    ARIMA_PLUS trained on Jan 2017 - May 2018
--   arima_3m     ARIMA_PLUS trained on Mar - May 2018 only (same history length as REES46)
--   xgb_17m      BOOSTED_TREE_REGRESSOR (XGBoost) trained on Jan 2017 - May 2018, direct multi-horizon:
--                weekly forecast origins, target = orders / mean of the 28 days before the origin, so the
--                trees learn weekday, holiday and horizon shape instead of extrapolating a trend
--   timesfm      AI.FORECAST (TimesFM, pretrained, no training) on the Jan 2017 - May 2018 history
--   promedio_3m  naive reference: Mar - May 2018 daily mean of each series, held flat
-- Test: 1 Jun - 22 Aug 2018 (later days are incomplete in the public dataset). Tramos mirror sql/16:
--   '1-14 jun' (two weeks), 'jun-jul' (61 days, includes the first 14), 'agosto' (1-22 Aug).
-- Series: daily orders of each common category with >= 15 orders/day in Jan-May 2018, plus 'total'.
-- Olist has no full second year either, so yearly seasonality is still out of reach.
-- Input is fact_pedidos (MB); training and AI.FORECAST cost cents.

DECLARE fin_entrenamiento DATE DEFAULT '2018-05-31';
-- Brazilian national holidays (carnival, Good Friday, Corpus Christi included) inside the history
DECLARE feriados ARRAY<DATE> DEFAULT [
  DATE '2017-01-01', '2017-02-27', '2017-02-28', '2017-04-14', '2017-04-21', '2017-05-01', '2017-06-15',
  '2017-09-07', '2017-10-12', '2017-11-02', '2017-11-15', '2017-12-25', '2018-01-01', '2018-02-12',
  '2018-02-13', '2018-03-30', '2018-04-21', '2018-05-01', '2018-05-31'];

CREATE OR REPLACE VIEW ecommerce.v_pedidos_olist_dia
OPTIONS (labels = [('capa', 'gold')],
         description = 'Pedidos diarios de Olist por categoría común (>= 15 pedidos/día en ene-may 2018) y total, con ceros en días sin pedidos.')
AS
WITH base AS (
  SELECT fecha_compra AS fecha, categoria_comun, order_id
  FROM ecommerce.fact_pedidos
  WHERE fecha_compra BETWEEN '2017-01-01' AND '2018-08-22'
),
series AS (
  SELECT categoria_comun AS serie FROM base
  WHERE fecha BETWEEN '2018-01-01' AND '2018-05-31' AND categoria_comun IS NOT NULL
  GROUP BY categoria_comun
  HAVING COUNT(DISTINCT order_id) / COUNT(DISTINCT fecha) >= 15
  UNION ALL SELECT 'total'
),
conteo AS (
  SELECT fecha, categoria_comun AS serie, COUNT(DISTINCT order_id) AS pedidos FROM base GROUP BY fecha, categoria_comun
  UNION ALL
  SELECT fecha, 'total', COUNT(DISTINCT order_id) FROM base GROUP BY fecha
)
SELECT d AS fecha, s.serie, IFNULL(c.pedidos, 0) AS pedidos
FROM UNNEST(GENERATE_DATE_ARRAY('2017-01-01', '2018-08-22')) AS d
CROSS JOIN series AS s
LEFT JOIN conteo AS c ON c.fecha = d AND c.serie = s.serie;

CREATE OR REPLACE MODEL ecommerce.modelo_olist_17m
OPTIONS (model_type = 'ARIMA_PLUS', time_series_timestamp_col = 'fecha', time_series_data_col = 'pedidos',
         time_series_id_col = 'serie', data_frequency = 'DAILY', horizon = 83, holiday_region = 'BR')
AS SELECT fecha, serie, pedidos FROM ecommerce.v_pedidos_olist_dia WHERE fecha <= fin_entrenamiento;

CREATE OR REPLACE MODEL ecommerce.modelo_olist_3m
OPTIONS (model_type = 'ARIMA_PLUS', time_series_timestamp_col = 'fecha', time_series_data_col = 'pedidos',
         time_series_id_col = 'serie', data_frequency = 'DAILY', horizon = 83, holiday_region = 'BR')
AS SELECT fecha, serie, pedidos FROM ecommerce.v_pedidos_olist_dia
   WHERE fecha > DATE_SUB(fin_entrenamiento, INTERVAL 3 MONTH) AND fecha <= fin_entrenamiento;

-- Features for XGBoost: one row per (origin, series, horizon 1-83). Training origins every 7 days from
-- April 2017 with targets up to fin_entrenamiento; the test origin is fin_entrenamiento itself.
-- Only data up to each origin feeds its features (no leakage).
CREATE OR REPLACE TABLE ecommerce.ml_features_olist
OPTIONS (labels = [('capa', 'gold')],
         description = 'Variables del modelo XGBoost de Olist: por origen, serie y horizonte; nivel de 28 días, perfil por día de semana, feriado y razón objetivo.')
AS
WITH origenes AS (
  SELECT o, 'train' AS conjunto FROM UNNEST(GENERATE_DATE_ARRAY('2017-04-01', DATE_SUB(fin_entrenamiento, INTERVAL 1 DAY), INTERVAL 7 DAY)) AS o
  UNION ALL SELECT fin_entrenamiento, 'test'
),
nivel AS (
  SELECT o, serie, AVG(pedidos) AS nivel28
  FROM origenes JOIN ecommerce.v_pedidos_olist_dia ON fecha BETWEEN DATE_SUB(o, INTERVAL 27 DAY) AND o
  GROUP BY o, serie
),
perfil AS (
  SELECT o, serie, EXTRACT(DAYOFWEEK FROM fecha) AS dia_semana, AVG(pedidos) AS media_dia_semana
  FROM origenes JOIN ecommerce.v_pedidos_olist_dia ON fecha BETWEEN DATE_SUB(o, INTERVAL 55 DAY) AND o
  GROUP BY o, serie, dia_semana
),
objetivo AS (
  SELECT x.o, x.conjunto, h AS horizonte, DATE_ADD(x.o, INTERVAL h DAY) AS fecha
  FROM origenes AS x, UNNEST(GENERATE_ARRAY(1, 83)) AS h
  WHERE x.conjunto = 'test' OR DATE_ADD(x.o, INTERVAL h DAY) <= fin_entrenamiento
)
SELECT
  t.conjunto, t.o AS origen, t.fecha, v.serie, t.horizonte,
  EXTRACT(DAYOFWEEK FROM t.fecha) AS dia_semana,
  EXTRACT(DAY FROM t.fecha) AS dia_mes,
  CASE WHEN t.fecha IN UNNEST(feriados) THEN 'feriado'
       WHEN t.fecha BETWEEN '2017-11-24' AND '2017-11-27' THEN 'black_friday'
       ELSE 'normal' END AS evento,
  n.nivel28,
  ROUND(SAFE_DIVIDE(p.media_dia_semana, n.nivel28), 3) AS perfil_dia_semana,
  SAFE_DIVIDE(v.pedidos, n.nivel28) AS razon,
  v.pedidos
FROM objetivo AS t
JOIN ecommerce.v_pedidos_olist_dia AS v ON v.fecha = t.fecha
JOIN nivel AS n ON n.o = t.o AND n.serie = v.serie
JOIN perfil AS p ON p.o = t.o AND p.serie = v.serie AND p.dia_semana = EXTRACT(DAYOFWEEK FROM t.fecha)
WHERE n.nivel28 >= 1;

CREATE OR REPLACE MODEL ecommerce.modelo_olist_xgb
OPTIONS (model_type = 'BOOSTED_TREE_REGRESSOR', input_label_cols = ['razon'], data_split_method = 'NO_SPLIT',
         max_iterations = 150, learn_rate = 0.05, max_tree_depth = 4, subsample = 0.8, l2_reg = 1.0,
         early_stop = FALSE)
AS SELECT serie, horizonte, dia_semana, dia_mes, evento, perfil_dia_semana, razon
   FROM ecommerce.ml_features_olist WHERE conjunto = 'train';

-- Long table for the dashboard: real orders and every forecast for the test window
CREATE OR REPLACE TABLE ecommerce.ml_pronostico_olist
OPTIONS (labels = [('capa', 'gold')],
         description = 'Pedidos diarios de Olist: real (ene 2017 - ago 2018) y pronóstico jun-ago 2018 de ARIMA (17 y 3 meses), XGBoost, TimesFM y promedio de 3 meses.')
AS
WITH promedio AS (
  SELECT serie, ROUND(AVG(pedidos), 1) AS pedidos
  FROM ecommerce.v_pedidos_olist_dia
  WHERE fecha > DATE_SUB(fin_entrenamiento, INTERVAL 3 MONTH) AND fecha <= fin_entrenamiento
  GROUP BY serie
),
dias AS (
  SELECT DISTINCT fecha FROM ecommerce.v_pedidos_olist_dia WHERE fecha > fin_entrenamiento
)
SELECT fecha, serie, 'real' AS modelo, CAST(pedidos AS FLOAT64) AS pedidos FROM ecommerce.v_pedidos_olist_dia
UNION ALL
SELECT DATE(forecast_timestamp), serie, 'arima_17m', ROUND(forecast_value, 1)
FROM ML.FORECAST(MODEL ecommerce.modelo_olist_17m, STRUCT(83 AS horizon, 0.9 AS confidence_level))
UNION ALL
SELECT DATE(forecast_timestamp), serie, 'arima_3m', ROUND(forecast_value, 1)
FROM ML.FORECAST(MODEL ecommerce.modelo_olist_3m, STRUCT(83 AS horizon, 0.9 AS confidence_level))
UNION ALL
SELECT fecha, serie, 'xgb_17m', ROUND(GREATEST(predicted_razon, 0) * nivel28, 1)
FROM ML.PREDICT(MODEL ecommerce.modelo_olist_xgb, (SELECT * FROM ecommerce.ml_features_olist WHERE conjunto = 'test'))
UNION ALL
SELECT DATE(forecast_timestamp), serie, 'timesfm', ROUND(forecast_value, 1)
FROM AI.FORECAST(
  (SELECT TIMESTAMP(fecha) AS fecha, serie, pedidos FROM ecommerce.v_pedidos_olist_dia WHERE fecha <= fin_entrenamiento),
  data_col => 'pedidos', timestamp_col => 'fecha', id_cols => ['serie'], horizon => 83, confidence_level => 0.9)
UNION ALL
SELECT d.fecha, p.serie, 'promedio_3m', p.pedidos FROM dias AS d CROSS JOIN promedio AS p;

CREATE TEMP TABLE pares AS
SELECT
  fecha, serie,
  SUM(IF(modelo = 'real', pedidos, 0)) AS real,
  SUM(IF(modelo = 'arima_17m', pedidos, 0)) AS arima_17m,
  SUM(IF(modelo = 'arima_3m', pedidos, 0)) AS arima_3m,
  SUM(IF(modelo = 'xgb_17m', pedidos, 0)) AS xgb_17m,
  SUM(IF(modelo = 'timesfm', pedidos, 0)) AS timesfm,
  SUM(IF(modelo = 'promedio_3m', pedidos, 0)) AS promedio_3m,
  CASE WHEN fecha <= '2018-06-14' THEN '1-14 jun' WHEN fecha <= '2018-07-31' THEN 'jun-jul' ELSE 'agosto' END AS tramo
FROM ecommerce.ml_pronostico_olist
WHERE fecha > fin_entrenamiento
GROUP BY fecha, serie;

-- WAPE per series, tramo and method; 'jun-jul' includes the first 14 days
CREATE OR REPLACE TABLE ecommerce.ml_eval_olist
OPTIONS (labels = [('capa', 'gold')],
         description = 'Error (WAPE) por serie y tramo de ARIMA (17 y 3 meses), XGBoost, TimesFM y promedio de 3 meses frente a los pedidos reales de jun-ago 2018.')
AS
SELECT serie, t AS tramo,
  ROUND(100 * SUM(ABS(real - arima_17m)) / SUM(real), 1) AS error_arima_17m_pct,
  ROUND(100 * SUM(ABS(real - arima_3m)) / SUM(real), 1) AS error_arima_3m_pct,
  ROUND(100 * SUM(ABS(real - xgb_17m)) / SUM(real), 1) AS error_xgb_17m_pct,
  ROUND(100 * SUM(ABS(real - timesfm)) / SUM(real), 1) AS error_timesfm_pct,
  ROUND(100 * SUM(ABS(real - promedio_3m)) / SUM(real), 1) AS error_promedio_3m_pct,
  SUM(real) AS pedidos_reales
FROM pares
JOIN UNNEST(['1-14 jun', 'jun-jul', 'agosto']) AS t
  ON pares.tramo = t OR (t = 'jun-jul' AND pares.tramo = '1-14 jun')
GROUP BY serie, t;

-- Summary over the category series (the 'total' series is reported apart in ml_eval_olist)
CREATE OR REPLACE TABLE ecommerce.ml_resumen_olist
OPTIONS (labels = [('capa', 'gold')],
         description = 'Error ponderado (WAPE) por tramo de los cinco métodos sobre las categorías de Olist.')
AS
SELECT t AS tramo,
  ROUND(100 * SUM(ABS(real - arima_17m)) / SUM(real), 1) AS error_arima_17m_pct,
  ROUND(100 * SUM(ABS(real - arima_3m)) / SUM(real), 1) AS error_arima_3m_pct,
  ROUND(100 * SUM(ABS(real - xgb_17m)) / SUM(real), 1) AS error_xgb_17m_pct,
  ROUND(100 * SUM(ABS(real - timesfm)) / SUM(real), 1) AS error_timesfm_pct,
  ROUND(100 * SUM(ABS(real - promedio_3m)) / SUM(real), 1) AS error_promedio_3m_pct
FROM pares
JOIN UNNEST(['1-14 jun', 'jun-jul', 'agosto']) AS t
  ON pares.tramo = t OR (t = 'jun-jul' AND pares.tramo = '1-14 jun')
WHERE serie != 'total'
GROUP BY t;

SELECT * FROM ecommerce.ml_resumen_olist ORDER BY tramo;
