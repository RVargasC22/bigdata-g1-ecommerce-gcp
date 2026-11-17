"""API de exposición: sirve las tablas gold de BigQuery a tableros, apps y modelos.

Solo lee tablas agg_* y ml_* (nunca events_raw) y cada consulta lleva un tope de bytes facturados.
"""
import os
from datetime import date

from fastapi import FastAPI, HTTPException, Query
from google.cloud import bigquery

PROJECT = os.environ.get("PROJECT_ID", "bigdata-g1-ecommerce-1105")
DATASET = os.environ.get("DATASET", "ecommerce")
MAX_BYTES = int(os.environ.get("MAX_BYTES_BILLED", 10 * 1024**3))

app = FastAPI(title="eCommerce GCP · API de exposición", version="1.0")
bq = bigquery.Client(project=PROJECT)


def query(sql: str, params: list) -> list[dict]:
    cfg = bigquery.QueryJobConfig(query_parameters=params, maximum_bytes_billed=MAX_BYTES)
    return [dict(r) for r in bq.query(sql, job_config=cfg).result()]


@app.get("/health")
def health():
    return {"status": "ok", "project": PROJECT}


@app.get("/ventas/diarias")
def ventas_diarias(
    desde: date = date(2020, 1, 1),
    hasta: date = date(2020, 1, 31),
    categoria: str | None = Query(None, description="categoria_comun, ej. electronica"),
):
    """Compras e ingresos por día y categoría (agg_embudo_categoria_dia)."""
    sql = f"""
      SELECT fecha, categoria_comun, SUM(compras) AS compras, SUM(ingresos) AS ingresos
      FROM `{PROJECT}.{DATASET}.agg_embudo_categoria_dia`
      WHERE fecha BETWEEN @desde AND @hasta
        AND (@cat IS NULL OR categoria_comun = @cat)
      GROUP BY fecha, categoria_comun ORDER BY fecha, categoria_comun LIMIT 5000"""
    rows = query(sql, [
        bigquery.ScalarQueryParameter("desde", "DATE", desde),
        bigquery.ScalarQueryParameter("hasta", "DATE", hasta),
        bigquery.ScalarQueryParameter("cat", "STRING", categoria)])
    return [{**r, "ingresos": float(r["ingresos"])} for r in rows]


@app.get("/embudo/{categoria}")
def embudo(categoria: str, desde: date = date(2020, 1, 1), hasta: date = date(2020, 1, 31)):
    """Sesiones view -> cart -> purchase de una categoría y tasa de conversión."""
    sql = f"""
      SELECT SUM(sesiones_view) AS view, SUM(sesiones_cart) AS cart, SUM(sesiones_purchase) AS purchase
      FROM `{PROJECT}.{DATASET}.agg_embudo_categoria_dia`
      WHERE categoria_comun = @cat AND fecha BETWEEN @desde AND @hasta"""
    r = query(sql, [bigquery.ScalarQueryParameter("cat", "STRING", categoria),
                    bigquery.ScalarQueryParameter("desde", "DATE", desde),
                    bigquery.ScalarQueryParameter("hasta", "DATE", hasta)])[0]
    if not r["view"]:
        raise HTTPException(404, f"sin datos para {categoria}")
    return {**r, "conversion_pct": round(100 * r["purchase"] / r["view"], 2)}


@app.get("/pronostico")
def pronostico(categoria: str, serie: str | None = Query(None, description="real | pronostico | referencia")):
    """Serie diaria real, pronosticada (ARIMA_PLUS) y de referencia (ml_pronostico_demanda)."""
    sql = f"""
      SELECT fecha, serie, compras, limite_inferior, limite_superior
      FROM `{PROJECT}.{DATASET}.ml_pronostico_demanda`
      WHERE categoria_comun = @cat AND (@serie IS NULL OR serie = @serie)
      ORDER BY fecha, serie LIMIT 5000"""
    rows = query(sql, [bigquery.ScalarQueryParameter("cat", "STRING", categoria),
                       bigquery.ScalarQueryParameter("serie", "STRING", serie)])
    if not rows:
        raise HTTPException(404, f"sin datos para {categoria}")
    return rows


@app.get("/pronostico/resumen")
def pronostico_resumen():
    """Error del modelo frente al promedio de referencia (ml_resumen_pronostico)."""
    return query(f"SELECT * FROM `{PROJECT}.{DATASET}.ml_resumen_pronostico`", [])[0]


@app.get("/stream/minuto")
def stream_minuto(limite: int = Query(60, ge=1, le=1000)):
    """Últimos minutos agregados por el pipeline Beam (stream_categoria_minuto)."""
    sql = f"""
      SELECT * FROM `{PROJECT}.{DATASET}.stream_categoria_minuto`
      ORDER BY 1 DESC LIMIT @n"""
    rows = query(sql, [bigquery.ScalarQueryParameter("n", "INT64", limite)])
    return [{k: (float(v) if hasattr(v, "as_tuple") else v) for k, v in r.items()} for r in rows]
