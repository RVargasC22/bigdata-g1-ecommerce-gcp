"""Genera docs/p3/calculadora_consumo.xlsx: estimación de costo del primer año (fórmulas vivas)."""
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
from pathlib import Path

wb = Workbook()
ws = wb.active; ws.title = "Supuestos"
bold = Font(bold=True); inp = PatternFill("solid", fgColor="FFF2CC"); hdr = PatternFill("solid", fgColor="D9E1F2")

ws.append(["Parámetro", "Valor", "Unidad", "Fuente / nota"])
rows = [
 ("Eventos por mes (REES46)", 70_000_000, "eventos", "410 M en 6 meses medidos ≈ 68 M/mes"),
 ("Bytes por evento en BigQuery", 130, "bytes", "events_raw ≈ 103 GB lógicos / 410 M eventos (medido, incl. silver/gold)"),
 ("Almacenamiento inicial", 103, "GB", "medido BigQuery lógico"),
 ("Almacenamiento inicial GCS", 19.6, "GB", "medido"),
 ("Consultas programadas/mes (TiB escaneados)", 1.9, "TiB", "60 GiB por corrida diaria con carga activa × 30 / 1024 ≈ 1,8"),
 ("Consultas de tableros y API (TiB/mes)", 0.1, "TiB", "tablas gold agregadas: ~0,2 MB por consulta (medido)"),
 ("Horas Dataflow streaming por mes", 120, "h", "supuesto: 4 h/día de ventana pico, no 24x7"),
 ("vCPU por worker", 4, "vCPU", "n1-standard-4 (plantilla)"),
 ("Memoria por worker", 15, "GB", "n1-standard-4"),
 ("Workers promedio", 1.5, "workers", "medido 1–2 en replay"),
 ("GB publicados en Pub/Sub por mes", 35, "GB", "70 M × 0,5 KB"),
 ("Peticiones API por mes", 1_000_000, "req", "supuesto"),
 ("vCPU-segundos Cloud Run por mes", 300_000, "vCPU·s", "supuesto: 0,3 s por petición × 1 vCPU"),
 ("Entrenamientos BigQuery ML por año", 12, "veces", "1 por mes (medido 50,8 GB por entrenamiento XGBoost)"),
 ("GB por entrenamiento BQML", 50.8, "GB", "medido"),
]
for r in rows: ws.append(list(r))
ws.append([]); ws.append(["Precios de lista (USD)", "Valor", "Unidad", "Verificar en cloud.google.com/products/calculator"])
prices = [
 ("BigQuery consultas bajo demanda", 6.25, "USD/TiB", "primer 1 TiB/mes gratis"),
 ("BigQuery TiB gratis por mes", 1, "TiB", ""),
 ("BigQuery almacenamiento activo", 0.02, "USD/GB-mes", "10 GiB/mes gratis (ignorado)"),
 ("BigQuery BQML XGBoost", 250, "USD/TiB", "tarifa BQML de modelos boosted tree (verificar)"),
 ("Cloud Storage Standard (us-central1)", 0.02, "USD/GB-mes", ""),
 ("Pub/Sub por TiB", 40, "USD/TiB", "10 GiB/mes gratis (ignorado)"),
 ("Dataflow streaming vCPU", 0.069, "USD/vCPU-h", ""),
 ("Dataflow streaming memoria", 0.003557, "USD/GB-h", ""),
 ("Storage Write API", 0.025, "USD/GiB", "primeros 2 TiB/mes gratis (ignorado)"),
 ("Cloud Run vCPU-segundo", 0.000024, "USD/vCPU·s", "2 M req y 180 k vCPU·s gratis (ignorado)"),
 ("Cloud Run peticiones", 0.40, "USD/millón", ""),
 ("Dataplex + Monitoring + Secret Manager", 15, "USD/mes", "medido: Dataplex 0,87 PEN en 6 días ≈ 3,5 USD/mes; margen"),
 ("Looker Studio", 0, "USD/mes", "gratuito"),
]
start = ws.max_row + 1
for p in prices: ws.append(list(p))
for c in ws[1]: c.font = bold; c.fill = hdr
ws.cell(row=start-1, column=1).font = bold
for r in range(2, ws.max_row+1):
    if ws.cell(r,2).value is not None: ws.cell(r,2).fill = inp
ws.column_dimensions["A"].width = 46; ws.column_dimensions["B"].width = 14; ws.column_dimensions["C"].width = 14; ws.column_dimensions["D"].width = 80

# nombres de celda por posición
S = {r[0]: f"Supuestos!$B${i+2}" for i, r in enumerate(rows)}
P = {p[0]: f"Supuestos!$B${start+i}" for i, p in enumerate(prices)}

c = wb.create_sheet("Costo mensual")
c.append(["Servicio", "Costo mensual (USD)", "Fórmula resumida"])
items = [
 ("BigQuery consultas", f"=MAX(0,{S['Consultas programadas/mes (TiB escaneados)']}+{S['Consultas de tableros y API (TiB/mes)']}-{P['BigQuery TiB gratis por mes']})*{P['BigQuery consultas bajo demanda']}", "(TiB − 1 gratis) × 6,25"),
 ("BigQuery almacenamiento (promedio año 1)", f"=({S['Almacenamiento inicial']}+{S['Eventos por mes (REES46)']}*{S['Bytes por evento en BigQuery']}/1000000000*6)*{P['BigQuery almacenamiento activo']}", "(inicial + crecimiento medio 6 meses) × 0,02"),
 ("Cloud Storage", f"={S['Almacenamiento inicial GCS']}*{P['Cloud Storage Standard (us-central1)']}", "GB × 0,02"),
 ("Pub/Sub", f"={S['GB publicados en Pub/Sub por mes']}/1024*{P['Pub/Sub por TiB']}", "TiB × 40"),
 ("Dataflow streaming", f"={S['Horas Dataflow streaming por mes']}*{S['Workers promedio']}*({S['vCPU por worker']}*{P['Dataflow streaming vCPU']}+{S['Memoria por worker']}*{P['Dataflow streaming memoria']})", "h × workers × (vCPU y memoria)"),
 ("Storage Write API (gratis < 2 TiB)", "=0", "35 GB/mes ≪ 2 TiB"),
 ("Cloud Run (API)", f"={S['Peticiones API por mes']}/1000000*{P['Cloud Run peticiones']}+{S['vCPU-segundos Cloud Run por mes']}*{P['Cloud Run vCPU-segundo']}", "peticiones + vCPU·s (sin capa gratuita)"),
 ("BigQuery ML (reentrenos, mensual)", f"={S['Entrenamientos BigQuery ML por año']}/12*{S['GB por entrenamiento BQML']}/1024*{P['BigQuery BQML XGBoost']}", "veces/12 × TiB × tarifa BQML"),
 ("Gobierno, monitoreo, secretos", f"={P['Dataplex + Monitoring + Secret Manager']}", "fijo"),
 ("Looker Studio", f"={P['Looker Studio']}", "gratis"),
]
for it in items: c.append(list(it))
n = c.max_row
c.append(["TOTAL mensual", f"=SUM(B2:B{n})", ""])
c.append(["TOTAL primer año", f"=B{n+1}*12", "12 meses"])
for cell in c[1]: cell.font = bold; cell.fill = hdr
for r in (n+1, n+2): c.cell(r,1).font = bold; c.cell(r,2).font = bold
c.column_dimensions["A"].width = 58; c.column_dimensions["B"].width = 22; c.column_dimensions["C"].width = 50
for r in range(2, c.max_row+1): c.cell(r,2).number_format = '#,##0.00'

k = wb.create_sheet("Escenarios")
k.append(["Escenario", "Multiplicador de volumen", "Costo anual aprox. (USD)", "Nota"])
for i, (nm, m, nt) in enumerate([("Base (este proyecto)", 1, "volumen medido"), ("Crecimiento ×3", 3, "campaña / más tiendas"), ("Crecimiento ×10", 10, "revisar reservas BigQuery (slots) a partir de aquí")], start=2):
    k.append([nm, m, f"='Costo mensual'!$B${n+2}*B{i}", nt])
for cell in k[1]: cell.font = bold; cell.fill = hdr
for col, w in zip("ABCD", (26, 24, 26, 60)): k.column_dimensions[col].width = w
for r in range(2, 5): k.cell(r,3).number_format = '#,##0'
k.append([]); k.append(["Aproximación lineal: ignora capas gratuitas y descuentos por compromiso. Referencia medida: facturación real 1–6 nov 2026 = S/ 8,75 bruto, cubierta por créditos."])
wb.properties.creator = wb.properties.lastModifiedBy = "Grupo 1 - Big Data UTEC"
wb.properties.title = "Calculadora de consumo - año 1"
wb.save(Path(__file__).with_name("calculadora_consumo.xlsx"))
