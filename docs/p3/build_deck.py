"""Genera docs/p3/Sustentacion_P3.pptx con officecli (batch JSON)."""
import json, subprocess, sys
from pathlib import Path

OUT = str(Path(__file__).with_name("Sustentacion_P3.pptx"))
P, S, A, TXT, MUT, LIGHT = "065A82", "1C7293", "E8A33D", "2B3A4E", "6B8FAA", "EEF4F8"
ops = []
n = 0

def slide(bg="FFFFFF"):
    global n; n += 1
    ops.append({"command": "add", "parent": "/", "type": "slide", "props": {"layout": "blank", "background": bg}})

def shp(x, y, w, h, text="", size=18, color=TXT, bold=False, font="Calibri", fill=None, preset=None,
        align="left", valign="top", name=None):
    pr = {"x": f"{x}cm", "y": f"{y}cm", "width": f"{w}cm", "height": f"{h}cm", "font": font, "size": str(size),
          "color": color, "bold": str(bold).lower(), "align": align, "valign": valign,
          "fill": fill or "none", "line": "none"}
    if text: pr["text"] = text
    if preset: pr["preset"] = preset
    if name: pr["name"] = name
    ops.append({"command": "add", "parent": f"/slide[{n}]", "type": "shape", "props": pr})

def title(t, dark=False):
    shp(1.5, 1.0, 30.8, 2.2, t, 36, "FFFFFF" if dark else P, True, "Georgia", valign="middle")

def notes(t):
    ops.append({"command": "add", "parent": f"/slide[{n}]", "type": "notes", "props": {"text": t}})

def footer():
    shp(1.5, 17.6, 24, 0.9, "Grupo 1 · Big Data · UTEC Posgrado · P3", 10, MUT)
    shp(29.5, 17.6, 2.8, 0.9, str(n), 10, MUT, align="right")

# 1 Portada
slide(P)
shp(0, 0, 1.2, 19.05, fill=A)
shp(3, 5.2, 28, 4.2, "Plataforma eCommerce en Google Cloud", 44, "FFFFFF", True, "Georgia", valign="middle")
shp(3, 9.6, 28, 1.8, "Exposición de datos, demo end-to-end y sustentación (P3)", 24, "CADCFC")
shp(3, 13.0, 28, 1.2, "Grupo 1 · Big Data · UTEC Posgrado", 18, "FFFFFF")
shp(3, 14.4, 28, 1.2, "21 de noviembre de 2026 · Proyecto bigdata-g1-ecommerce-1105", 18, "CADCFC")

# 2 Resumen ejecutivo
slide(); title("Resumen ejecutivo y alcance")
for i, (h, b) in enumerate([("Qué se implementó", "Plataforma de datos en GCP: ingesta batch y streaming, capas bronze, silver y gold, tableros, pronóstico y API."),
                            ("Con qué datos", "REES46: 410 M eventos (oct 2019 – abr 2020). Olist: 99 470 pedidos (2016–2018)."),
                            ("Qué entregamos en P3", "API de exposición sobre las tablas gold, demo en vivo, calculadora de costo del primer año.")]):
    x = 1.5 + i * 10.54
    shp(x, 4.2, 9.78, 11.5, fill=LIGHT, preset="roundRect")
    shp(x + .5, 4.6, 8.8, 2.2, h, 22, P, True, "Georgia")
    shp(x + .5, 7.0, 8.8, 8.4, b, 20)
footer()

# 3 Situación actual
slide(); title("Situación actual")
rows = [("410M", "eventos en events_raw"), ("3", "capas: bronze, silver, gold"), ("7", "páginas de tablero en Looker Studio"), ("0", "mensajes perdidos en 9,99 M de replay")]
for i, (big, sub) in enumerate(rows):
    x = 1.5 + i * 7.9
    shp(x, 4.2, 7.14, 7, fill=P, preset="roundRect")
    shp(x, 5.0, 7.14, 2.8, big, 60, "FFFFFF", True, "Georgia", align="center", valign="middle")
    shp(x + .3, 8.4, 6.54, 2.2, sub, 16, "CADCFC", align="center")
shp(1.5, 12.4, 30.8, 3.8, "Todo está desplegado y probado sobre datos reales. Las consultas programadas están en pausa desde el 6 de nov (los datos ya no cambian) y las reactivamos para la demo.", 20)
footer()

# 4 KPIs
slide(); title("Criterios de éxito en formato KPI")
k = [("Meta", "Medido", None)]
shp(1.5, 3.7, 30.8, 1.3, "Cada KPI con su meta y el resultado medido", 20, MUT)
data = [("Pérdida de mensajes", "0 %", "0 de 9 990 850"), ("Lag máximo de Dataflow", "≤ 60 s", "7 s"), ("Conciliación stream vs batch", "100 %", "379 de 379"),
        ("Bytes por consulta de tablero", "< 1 GB", "≈ 0,2 MB"), ("Costo mensual (sin créditos)", "< US$ 150", "≈ US$ 105")]
shp(1.5, 5.2, 14, 1, "Indicador", 16, MUT, True); shp(16.5, 5.2, 7, 1, "Meta", 16, MUT, True); shp(24.2, 5.2, 8, 1, "Resultado", 16, MUT, True)
for i, (a, m, r) in enumerate(data):
    y = 6.4 + i * 2.0
    shp(1.5, y, 30.8, 1.8, fill=LIGHT if i % 2 == 0 else "FFFFFF", preset="rect")
    shp(1.8, y, 14, 1.8, a, 20, valign="middle"); shp(16.5, y, 7, 1.8, m, 20, valign="middle")
    shp(24.2, y, 8, 1.8, r, 22, P, True, valign="middle")
shp(1.5, 16.7, 30.8, 0.9, "ARIMA_PLUS no supera al promedio simple (36 % vs 20 %): falta historia.", 14, MUT)
footer()

# 5 Productos
slide(); title("Productos tecnológicos")
prods = [("Cloud Storage", "Zona raw versionada"), ("Pub/Sub", "Cola de eventos, 7 días"), ("Dataflow + Apache Beam", "Streaming y agregación"),
         ("BigQuery", "Almacén: bronze, silver, gold"), ("BigQuery ML", "ARIMA_PLUS y XGBoost"), ("Cloud Run + FastAPI", "API de exposición"),
         ("Looker Studio", "Tableros"), ("Dataplex y Monitoring", "Gobierno y alertas")]
for i, (a, b) in enumerate(prods):
    c, r = i % 4, i // 4
    x = 1.5 + c * 7.9; y = 4.4 + r * 6.4
    shp(x, y, 7.14, 6.0, fill=LIGHT, preset="roundRect")
    shp(x, y, 7.14, .5, fill=P if r == 0 else S)
    shp(x + .3, y + .9, 6.54, 2.7, a, 20, P, True, "Georgia")
    shp(x + .3, y + 3.5, 6.54, 2.4, b, 18)
footer()

# 6 Supuestos
slide(); title("Dependencias, supuestos y exclusiones")
cols = [("Dependencias", ["Facturación UTEC y créditos", "Espejo REES46 para dic–abr", "Red de oficina: firewall con inspección SSL"]),
        ("Supuestos", ["Inventario derivado: 50 unidades por semana", "70 M eventos/mes en el año 1", "Precios de lista de GCP"]),
        ("Fuera de alcance", ["Licencia comercial de datos", "Reglas de negocio de producción", "Enmascaramiento dinámico (requiere organización)"])]
for i, (h, items) in enumerate(cols):
    x = 1.5 + i * 10.54
    shp(x, 4.2, 9.78, 1.8, h, 22, "FFFFFF", True, "Georgia", fill=P if i != 2 else MUT, align="center", valign="middle")
    shp(x, 6.0, 9.78, 10, fill=LIGHT)
    shp(x + .4, 6.5, 9.0, 9, "\n".join(items), 18)
footer()

# 7 Arquitectura final
slide(); title("Arquitectura final")
boxes = [("Orígenes", "CSV + replay"), ("Pub/Sub", "eventos"), ("Dataflow", "Beam + UDF"), ("BigQuery", "bronze → gold"), ("API · Looker", "consumo")]
w, g = 5.6, 0.7
for i, (a, b) in enumerate(boxes):
    x = 1.5 + i * (w + g)
    shp(x, 6.0, w, 3.8, f"{a}\n{b}", 20, "FFFFFF", True, "Georgia", fill=P if i % 2 == 0 else S, preset="roundRect", align="center", valign="middle", name=f"B{i}")
for i in range(4):
    ops.append({"command": "add", "parent": f"/slide[{n}]", "type": "connector",
                "props": {"from": f"/slide[{n}]/shape[@name=B{i}]", "to": f"/slide[{n}]/shape[@name=B{i+1}]", "shape": "straight", "color": TXT, "tailEnd": "triangle"}})
shp(1.5, 11.2, 14.9, 4.8, "Transversal\nCuentas de servicio por componente\nGobierno: Dataplex, policy tags, row access\nAlertas, DR y consultas programadas", 18, fill=LIGHT)
shp(17.4, 11.2, 14.9, 4.8, "Primer año\nAPI en Cloud Run lee solo tablas agg_* y ml_*\nDataflow solo en ventanas pico\nTope de bytes facturados por consulta", 18, fill=LIGHT)
footer()

# 8 API
slide(); title("Capa de exposición: API sobre BigQuery")
eps = [("GET /ventas/diarias", "Compras e ingresos por día y categoría"), ("GET /embudo/{categoria}", "view → cart → purchase y conversión"),
       ("GET /pronostico", "Serie real, ARIMA_PLUS y referencia"), ("GET /pronostico/resumen", "Error del modelo vs referencia"), ("GET /stream/minuto", "Últimos minutos del pipeline Beam")]
for i, (a, b) in enumerate(eps):
    y = 4.3 + i * 2.5
    shp(1.5, y, 11.5, 2.1, a, 18, "FFFFFF", True, "Consolas", fill=P, preset="roundRect", valign="middle", align="center")
    shp(13.6, y, 18.7, 2.1, b, 20, valign="middle")
shp(1.5, 17.0, 30.8, 0.9, "Consultas parametrizadas, solo tablas gold, tope de 10 GB facturados por consulta.", 14, MUT)
footer()

# 9 Calculadora
slide(); title("Calculadora de consumo: primer año")
ops.append({"command": "add", "parent": f"/slide[{n}]", "type": "chart", "props": {"chartType": "bar", "series1.name": "USD por mes", "series1.values": "59.3,15.0,12.4,7.6,6.3,3.2,1.8", "series1.color": P,
            "categories": "Dataflow,Gobierno y monitoreo,BigQuery ML,Cloud Run,BigQuery consultas,BigQuery storage,GCS y Pub/Sub", "x": "1.5cm", "y": "3.6cm", "width": "20cm", "height": "13.6cm"}})
shp(22.8, 4.2, 9.5, 11.6, fill=P, preset="roundRect")
shp(22.8, 5.0, 9.5, 2.6, "US$ 1 265", 40, "FFFFFF", True, "Georgia", align="center", valign="middle")
shp(23.1, 7.8, 8.9, 1.2, "estimado anual", 16, "CADCFC", align="center")
shp(23.1, 9.8, 8.9, 5.6, "≈ US$ 105 al mes a precio de lista, sin capas gratuitas ni créditos.\nDataflow pesa más de la mitad.", 18, "FFFFFF")
footer()

# 10 Demo
slide(); title("Demo end-to-end")
steps = ["1 Replay a Pub/Sub", "2 Dataflow procesa", "3 Llega a BigQuery", "4 API responde", "5 Looker muestra"]
for i, s_ in enumerate(steps):
    x = 1.5 + i * 6.3
    shp(x, 4.4, 5.6, 3.4, s_, 20, "FFFFFF", True, "Georgia", fill=P if i % 2 == 0 else S, preset="roundRect", align="center", valign="middle", name=f"D{i}")
for i in range(4):
    ops.append({"command": "add", "parent": f"/slide[{n}]", "type": "connector",
                "props": {"from": f"/slide[{n}]/shape[@name=D{i}]", "to": f"/slide[{n}]/shape[@name=D{i+1}]", "shape": "straight", "color": TXT, "tailEnd": "triangle"}})
shp(1.5, 9.4, 30.8, 7.2, "Caso de uso: monitorear en tiempo real las ventas por categoría durante el pico.\nTramo del 17/11/2019 a 10x: 227 830 eventos.\nVerificación: 379 de 379 combinaciones minuto × categoría iguales al cálculo batch.\nLa API devuelve el pronóstico y el estado del stream.", 20)
footer()

# 11 Conclusiones
slide(); title("Conclusiones")
shp(1.5, 4.2, 30.8, 12, "• La plataforma ingiere, transforma y expone datos de eCommerce sin perder mensajes.\n• Costo estimado: US$ 105 al mes, dominado por Dataflow en streaming.\n• El pronóstico necesita al menos un año de historia para superar al promedio.\n• La calidad de datos fue el hallazgo mayor: la taxonomía cambió desde diciembre.", 22)
shp(0, 0, 0.6, 19.05, fill=A)
footer()

# 12 Next steps
slide(); title("Next Steps")
ns = [("1", "Licencia comercial de datos y fuente en producción"), ("2", "Reducir Dataflow con autoscaling y ventanas más cortas"), ("3", "Reentrenar con un año de historia y XGBoost"), ("4", "Autenticación y cuotas por cliente en la API")]
for i, (a, b) in enumerate(ns):
    y = 4.3 + i * 3.1
    shp(1.5, y, 2.4, 2.4, a, 28, "FFFFFF", True, "Georgia", fill=P, preset="ellipse", align="center", valign="middle")
    shp(4.6, y, 27.7, 2.4, b, 22, valign="middle")
footer()

import tempfile, os
subprocess.run(["officecli", "create", OUT], check=True)
with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
    json.dump(ops, f)
r = subprocess.run(["officecli", "batch", OUT, "--input", f.name], capture_output=True, text=True)
print(r.stdout[-600:], r.stderr[-600:])
