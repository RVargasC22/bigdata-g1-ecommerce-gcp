-- Demand forecast with BigQuery ML (ARIMA_PLUS): one time series of daily purchases per common category.
-- Use: anticipate how much each category will sell to plan stock (fact_inventario assumes a flat 50 units
-- per product per week) and Dataflow capacity before a peak.
-- Validation with real data: the model is trained only with Oct-Dec 2019 and its Jan-Mar 2020 forecast is
-- compared with the real Jan-Mar 2020 purchases (ingest/fetch_2020.sh), which the model never saw.
--   tramo '1-14 ene'  operational horizon (next two weeks)
--   tramo 'ene-feb'   60 days
--   tramo 'marzo'     COVID-19 lockdown in Russia: a structural break no model trained on 2019 can foresee
-- ARIMA_PLUS picks the ARIMA order per series, models weekly seasonality and, by default, cleans spikes
-- such as the 15-17 Nov peak so they do not distort the baseline. Input is the gold table
-- agg_embudo_categoria_dia (KB), so training costs cents.

DECLARE fin_entrenamiento DATE DEFAULT '2019-12-31';

-- Daily purchases per category; categories with at least 100 purchases per day on average in 2019
CREATE OR REPLACE VIEW ecommerce.v_compras_categoria_dia
OPTIONS (labels = [('capa', 'gold')], description = 'Compras diarias por categoría común (entrada del pronóstico ARIMA_PLUS).')
AS
SELECT fecha, categoria_comun, SUM(compras) AS compras, SUM(ingresos) AS ingresos
FROM ecommerce.agg_embudo_categoria_dia
WHERE categoria_comun IN (
  SELECT categoria_comun FROM ecommerce.agg_embudo_categoria_dia
  WHERE categoria_comun != 'sin_categoria' AND fecha <= '2019-12-31'
  GROUP BY categoria_comun
  HAVING SUM(compras) / COUNT(DISTINCT fecha) >= 100)
GROUP BY fecha, categoria_comun;

DROP MODEL IF EXISTS ecommerce.modelo_demanda_backtest;

CREATE OR REPLACE MODEL ecommerce.modelo_demanda
OPTIONS (model_type = 'ARIMA_PLUS', time_series_timestamp_col = 'fecha', time_series_data_col = 'compras',
         time_series_id_col = 'categoria_comun', data_frequency = 'DAILY', horizon = 91)
AS SELECT fecha, categoria_comun, compras FROM ecommerce.v_compras_categoria_dia WHERE fecha <= fin_entrenamiento;

-- Long table for the dashboard: real purchases (Oct 2019 - Mar 2020) and forecast (Jan-Mar 2020, 90 % interval)
CREATE OR REPLACE TABLE ecommerce.ml_pronostico_demanda
OPTIONS (labels = [('capa', 'gold')],
         description = 'Compras diarias por categoría: real (oct 2019 - mar 2020) y pronóstico ene-mar 2020 de un modelo entrenado solo con 2019, con intervalo de 90 %.')
AS
SELECT fecha, categoria_comun, 'real' AS serie, compras, CAST(NULL AS FLOAT64) AS limite_inferior,
  CAST(NULL AS FLOAT64) AS limite_superior
FROM ecommerce.v_compras_categoria_dia
UNION ALL
SELECT DATE(forecast_timestamp), categoria_comun, 'pronostico', ROUND(forecast_value),
  ROUND(prediction_interval_lower_bound), ROUND(prediction_interval_upper_bound)
FROM ML.FORECAST(MODEL ecommerce.modelo_demanda, STRUCT(91 AS horizon, 0.9 AS confidence_level));

-- Real vs forecast per category and horizon (tramo)
CREATE TEMP TABLE pares AS
SELECT
  r.fecha, r.categoria_comun, r.compras AS real, p.compras AS pronostico, p.limite_inferior, p.limite_superior,
  CASE WHEN r.fecha <= '2020-01-14' THEN '1-14 ene' WHEN r.fecha <= '2020-02-29' THEN 'ene-feb' ELSE 'marzo' END AS tramo
FROM ecommerce.ml_pronostico_demanda r
JOIN ecommerce.ml_pronostico_demanda p USING (fecha, categoria_comun)
WHERE r.serie = 'real' AND p.serie = 'pronostico';

-- 'ene-feb' includes the first 14 days, so each tramo is cumulative except 'marzo'
CREATE OR REPLACE TABLE ecommerce.ml_eval_demanda
OPTIONS (labels = [('capa', 'gold')],
         description = 'Error del pronóstico por categoría y tramo frente a las compras reales de 2020 (datos no vistos al entrenar).')
AS
SELECT categoria_comun, t.tramo,
  ROUND(100 * SUM(ABS(real - pronostico)) / SUM(real), 1) AS error_pct,           -- WAPE
  ROUND(100 * (SUM(pronostico) - SUM(real)) / SUM(real), 1) AS sesgo_pct,
  ROUND(100 * COUNTIF(real BETWEEN limite_inferior AND limite_superior) / COUNT(*), 1) AS dentro_intervalo_pct,
  SUM(real) AS compras_reales, SUM(pronostico) AS compras_pronosticadas
FROM pares
JOIN UNNEST(['1-14 ene', 'ene-feb', 'marzo']) AS t
  ON pares.tramo = t.tramo OR (t.tramo = 'ene-feb' AND pares.tramo = '1-14 ene')
GROUP BY categoria_comun, t.tramo;

-- One-row summary for the dashboard KPIs (all categories together)
CREATE OR REPLACE TABLE ecommerce.ml_resumen_pronostico
OPTIONS (labels = [('capa', 'gold')],
         description = 'Error ponderado (WAPE) del pronóstico por tramo y cobertura del intervalo de 90 %, todas las categorías.')
AS
SELECT
  ROUND(100 * SUM(IF(tramo = '1-14 ene', ABS(real - pronostico), 0)) / SUM(IF(tramo = '1-14 ene', real, 0)), 1) AS error_14d_pct,
  ROUND(100 * SUM(IF(tramo != 'marzo', ABS(real - pronostico), 0)) / SUM(IF(tramo != 'marzo', real, 0)), 1) AS error_ene_feb_pct,
  ROUND(100 * COUNTIF(tramo != 'marzo' AND real BETWEEN limite_inferior AND limite_superior)
        / COUNTIF(tramo != 'marzo'), 1) AS dentro_intervalo_ene_feb_pct,
  ROUND(100 * SUM(IF(tramo = 'marzo', ABS(real - pronostico), 0)) / SUM(IF(tramo = 'marzo', real, 0)), 1) AS error_marzo_pct
FROM pares;
