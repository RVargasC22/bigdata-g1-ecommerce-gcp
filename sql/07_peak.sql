-- Section 2 evidence: daily volume (document query) and peak factor vs a normal November day.
SELECT
  DATE(event_time) AS dia,
  COUNT(*) AS eventos,
  ROUND(COUNT(*) / 1440, 0) AS eventos_por_minuto_promedio,
  COUNTIF(event_type = 'purchase') AS compras
FROM ecommerce.events_raw
WHERE DATE(event_time) BETWEEN '2019-11-01' AND '2019-12-05'
GROUP BY dia
ORDER BY dia;

-- Peak factor: busiest minute of each event day vs median per-minute rate of normal November days
-- (normal = 2019-11-01..2019-11-20, before the Black Friday run-up).
WITH por_minuto AS (
  SELECT TIMESTAMP_TRUNC(event_time, MINUTE) AS minuto, COUNT(*) AS eventos
  FROM ecommerce.events_raw
  WHERE DATE(event_time) BETWEEN '2019-11-01' AND '2019-12-05'
  GROUP BY minuto
),
normal AS (
  SELECT APPROX_QUANTILES(eventos, 100)[OFFSET(50)] AS p50_normal
  FROM por_minuto
  WHERE DATE(minuto) BETWEEN '2019-11-01' AND '2019-11-20'
)
SELECT
  DATE(minuto) AS dia,
  MAX(eventos) AS max_eventos_minuto,
  APPROX_QUANTILES(eventos, 100)[OFFSET(50)] AS p50_eventos_minuto,
  ANY_VALUE(p50_normal) AS p50_minuto_dia_normal,
  ROUND(MAX(eventos) / ANY_VALUE(p50_normal), 1) AS factor_pico_max,
  ROUND(APPROX_QUANTILES(eventos, 100)[OFFSET(50)] / ANY_VALUE(p50_normal), 1) AS factor_pico_p50
FROM por_minuto CROSS JOIN normal
WHERE DATE(minuto) IN ('2019-11-15', '2019-11-16', '2019-11-17', '2019-11-29', '2019-12-02')
GROUP BY dia
ORDER BY dia;
