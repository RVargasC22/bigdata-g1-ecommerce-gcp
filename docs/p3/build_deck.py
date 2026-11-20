"""Genera docs/p3/Sustentacion_P3.pptx (versión densa) con officecli (batch JSON)."""
import json, subprocess, tempfile, os
from pathlib import Path

HERE = Path(__file__).parent
OUT = str(HERE / "Sustentacion_P3.pptx")
IMG = str((HERE / ".." / "tutorial" / "img").resolve())
P, S, A, TXT, MUT, LIGHT = "065A82", "1C7293", "E8A33D", "2B3A4E", "6B8FAA", "EEF4F8"
ops = []
n = 0
spk = ""

def who(t):
    """Speaker and target time, prepended to the slide notes."""
    global spk; spk = f"[{t}] "

def slide(bg="FFFFFF"):
    global n; n += 1
    ops.append({"command": "add", "parent": "/", "type": "slide", "props": {"layout": "blank", "background": bg}})

def shp(x, y, w, h, text="", size=15, color=TXT, bold=False, font="Calibri", fill=None, preset=None,
        align="left", valign="top", name=None):
    pr = {"x": f"{x}cm", "y": f"{y}cm", "width": f"{w}cm", "height": f"{h}cm", "font": font, "size": str(size),
          "color": color, "bold": str(bold).lower(), "align": align, "valign": valign, "fill": fill or "none", "line": "none"}
    if text: pr["text"] = text
    if preset: pr["preset"] = preset
    if name: pr["name"] = name
    ops.append({"command": "add", "parent": f"/slide[{n}]", "type": "shape", "props": pr})

def title(t):
    shp(1.5, 0.8, 30.8, 1.9, t, 34, P, True, "Georgia", valign="middle")

def notes(t):
    ops.append({"command": "add", "parent": f"/slide[{n}]", "type": "notes", "props": {"text": spk + t}})

def footer():
    shp(1.5, 18.0, 24, 0.8, "Grupo 1 · Big Data · UTEC Posgrado · P3", 10, MUT)
    shp(29.5, 18.0, 2.8, 0.8, str(n), 10, MUT, align="right")

def pic(name, x, y, w, h, alt):
    ops.append({"command": "add", "parent": f"/slide[{n}]", "type": "picture",
                "props": {"src": f"{IMG}/{name}.png", "x": f"{x}cm", "y": f"{y}cm", "width": f"{w}cm", "height": f"{h}cm", "alt": alt}})

def table(x, y, cw, rows, size=14, rh=1.25, head=True):
    tw = sum(cw)
    for i, r in enumerate(rows):
        yy = y + i * rh
        hd = head and i == 0
        shp(x, yy, tw, rh, fill=P if hd else (LIGHT if i % 2 else "FFFFFF"), preset="rect")
        cx = x
        for j, c in enumerate(r):
            shp(cx + .2, yy, cw[j] - .3, rh, c, size, "FFFFFF" if hd else TXT, hd or j == 0, valign="middle")
            cx += cw[j]

def bullets(x, y, w, h, items, size=15, sep="\n"):
    shp(x, y, w, h, sep.join("• " + i for i in items), size)

def card(x, y, w, h, head, items, size=14, fill=LIGHT, hfill=P, sep="\n"):
    shp(x, y, w, h, fill=fill, preset="rect")
    shp(x, y, w, 1.5, head, 17, "FFFFFF", True, "Georgia", fill=hfill, valign="middle", align="center")
    bullets(x + .3, y + 1.8, w - .6, h - 2.0, items, size, sep)

def arrow(a, b):
    ops.append({"command": "add", "parent": f"/slide[{n}]", "type": "connector",
                "props": {"from": f"/slide[{n}]/shape[@name={a}]", "to": f"/slide[{n}]/shape[@name={b}]", "shape": "straight", "color": TXT, "tailEnd": "triangle"}})

def pill(x, y, w, h, text, fill, size=12, color="FFFFFF", font="Calibri"):
    shp(x, y, w, h, text, size, color, True, font, fill=fill, preset="roundRect", align="center", valign="middle")

def stat(x, y, w, h, big, sub, fill=P, bs=40):
    """Big-number tile: hero figure plus a short sublabel."""
    shp(x, y, w, h, fill=fill, preset="rect")
    shp(x, y + .4, w, 2.4, big, bs, "FFFFFF", True, "Georgia", align="center", valign="middle")
    shp(x + .3, y + 2.9, w - .6, h - 3.1, sub, 14, "E6EEF4", align="center")

GREEN = "3A8D5C"

def node(x, y, w, h, head, sub, fill, name, hs=17):
    """Diagram box: bold header plus a short subtitle."""
    shp(x, y, w, h, fill=fill, preset="roundRect", name=name)
    shp(x + .1, y + .3, w - .2, 1.2, head, hs, "FFFFFF", True, "Georgia", align="center", valign="middle")
    shp(x + .2, y + 1.5, w - .4, h - 1.6, sub, 13, "FFFFFF", align="center")

# 1 Portada
slide(P)
shp(0, 0, 1.2, 19.05, fill=A)
shp(3, 5.2, 28, 4.2, "Plataforma eCommerce en Google Cloud", 44, "FFFFFF", True, "Georgia", valign="middle")
shp(3, 9.6, 28, 1.8, "Exposición de datos, demo end-to-end y sustentación (P3)", 24, "CADCFC")
shp(3, 13.0, 28, 1.2, "Grupo 1 · Big Data · UTEC Posgrado", 18, "FFFFFF")
shp(3, 14.4, 28, 1.2, "21 de noviembre de 2026 · Proyecto bigdata-g1-ecommerce-1105", 18, "CADCFC")
shp(3, 15.8, 28, 1.2, "Repositorio: github.com/RVargasC22/bigdata-g1-ecommerce-gcp", 18, "FFFFFF")

# 2 Resumen ejecutivo
slide(); title("Resumen ejecutivo y alcance")
cols = [("Qué se implementó", "Batch y streaming", P, ["Bronze, silver y gold en BigQuery", "Plantilla de Dataflow y pipeline Beam propio",
            "BigQuery ML y Looker Studio (7 páginas)", "Gobierno, alertas, DR, Terraform y CI"]),
        ("Con qué datos", "410 M + 99 470", S, ["Eventos REES46, oct 2019 – abr 2020", "Pedidos Olist, Brasil 2016–2018",
            "Cruce por 18 categorías comunes", "Datos reales, no sintéticos"]),
        ("Qué entregamos en P3", "API + demo", A, ["5 endpoints con IAM sobre tablas gold", "Demo en vivo de extremo a extremo",
            "Calculadora del año 1 (×3 y ×10)", "Repositorio y tutorial reproducible"])]
for i, (head, big, col, items) in enumerate(cols):
    x = 1.5 + i * 10.5
    shp(x, 3.2, 9.9, 14.2, fill=LIGHT, preset="rect")
    shp(x, 3.2, 9.9, 1.5, head, 17, "FFFFFF", True, "Georgia", fill=col, valign="middle", align="center")
    shp(x + .3, 5.1, 9.3, 2.6, big, 26, col, True, "Georgia", align="center", valign="middle")
    bullets(x + .5, 8.2, 8.9, 9.0, items, 17, "\n\n")
footer()

# 3 Situación actual
slide(); title("Situación actual")
for i, (big, sub) in enumerate([("410M", "eventos en events_raw"), ("99 470", "pedidos Olist"), ("5,5x", "pico del 17/11/2019"), ("0", "mensajes perdidos de 9,99 M")]):
    x = 1.5 + i * 7.9
    shp(x, 3.2, 7.14, 4.6, fill=P, preset="rect")
    shp(x, 3.5, 7.14, 2.4, big, 44, "FFFFFF", True, "Georgia", align="center", valign="middle")
    shp(x + .2, 6.1, 6.74, 1.5, sub, 15, "CADCFC", align="center")
table(1.5, 8.4, [9, 21.8], [("Componente", "Estado"),
    ("Ingesta y almacenamiento", "Batch y streaming operativos; 410 M eventos; DR con snapshots y simulacro"),
    ("Transformación", "Silver y gold en BigQuery; Beam en Dataflow concilia 379 de 379 contra batch"),
    ("Calidad", "Deduplicación (21 696 filas) y chequeos ASSERT diarios; taxonomía de diciembre corregida"),
    ("Analítica", "Tablero de 7 páginas; pronóstico ARIMA_PLUS y XGBoost con validación contra datos reales"),
    ("Operación", "Consultas programadas en pausa desde el 6 de nov; se reactivan para la demo")], 14, 1.45)
footer()

# 4 KPIs
slide(); title("Criterios de éxito en formato KPI")
kpis = [("Pérdida de mensajes en replay", "0 %", "0 de 9 990 850", "docs/evidencia/replays.log", True),
    ("Lag máximo del sistema (Dataflow)", "≤ 60 s", "7 s", "metricas_pico.csv", True),
    ("Conciliación stream vs batch", "100 %", "379 de 379", "beam_conciliacion.txt", True),
    ("Mensajes inválidos a la cola de errores", "100 %", "3 de 3 por tipo", "events_deadletter", True),
    ("Bytes por consulta de tablero", "< 1 GB", "≈ 0,2 MB", "sql/09_bytes_scanned.sh", True),
    ("Costo mensual a precio de lista", "< US$ 150", "≈ US$ 105", "calculadora_consumo.xlsx", True),
    ("Intervalo de pronóstico de 90 %", "≈ 90 %", "93,5 % cubierto", "ml_resumen_pronostico", True),
    ("Error del pronóstico vs promedio simple", "menor", "36 % vs 20 %", "falta un año de historia", False)]
table(1.5, 3.2, [9.6, 4.4, 5.0, 8.4, 3.4], [("Indicador", "Meta", "Medido", "Evidencia", "Estado")] + [(k[0], k[1], "", k[3], "") for k in kpis], 14, 1.4)
for i, k in enumerate(kpis):
    yy = 3.2 + (i + 1) * 1.4
    shp(15.7, yy, 4.7, 1.4, k[2], 14, GREEN if k[4] else "B5532F", True, valign="middle")
    pill(29.1, yy + .3, 3.0, .8, "Cumple" if k[4] else "No cumple", GREEN if k[4] else A, 11)
shp(1.5, 16.3, 30.8, 1.4, "7 de 8 metas cumplidas. Las metas de lag, bytes y costo las fijamos para P3. El pronóstico no cumple y lo reportamos así: se necesita al menos un año de historia.", 13, MUT)
footer()

# 5 Productos
slide(); title("Productos tecnológicos a usar")
prods = [("Cloud Storage", "INGESTA", P, "Zona raw versionada, replays, lookup de Beam", "Barato y duradero; ciclo de vida"),
    ("Pub/Sub", "INGESTA", P, "Cola de eventos, retención 7 días, 2 suscripciones", "Absorbe picos; entrega al menos una vez"),
    ("Dataflow + Beam", "PROCESO", S, "Plantilla con UDF y pipeline propio en streaming", "Autoescala de 1 a 2 workers"),
    ("BigQuery", "ALMACÉN", TXT, "Bronze, silver y gold; vista materializada", "Sin servidores; cobro por uso"),
    ("BigQuery ML", "ALMACÉN", TXT, "ARIMA_PLUS, XGBoost y TimesFM", "Modelos en SQL, sin mover datos"),
    ("Cloud Run + FastAPI", "CONSUMO", A, "API de exposición, con cuenta sa-api", "Escala a cero; autenticación IAM"),
    ("Looker Studio", "CONSUMO", A, "7 páginas; solo lee tablas agg_* y ml_*", "Gratis; caché de 12 h"),
    ("Dataplex · Secret Manager", "GOBIERNO", MUT, "Linaje, glosario y secretos", "Gobierno sin código propio"),
    ("Monitoring · Terraform · CI", "OPERACIÓN", MUT, "Alertas, IaC (52 recursos), GitHub Actions", "Operación reproducible")]
for i, (name, layer, col, role, why) in enumerate(prods):
    x, y = 1.5 + (i % 3) * 10.54, 3.1 + (i // 3) * 5.0
    shp(x, y, 9.78, 4.6, fill=LIGHT, preset="rect")
    shp(x, y, 9.78, 1.4, fill=col, preset="rect")
    shp(x + .35, y, 9.1, 1.4, name, 16, "FFFFFF", True, "Georgia", valign="middle")
    shp(x + .35, y + 1.5, 9.1, .6, layer, 10, col, True)
    shp(x + .35, y + 2.0, 9.1, 1.4, role, 14, TXT, True)
    shp(x + .35, y + 3.25, 9.1, 1.3, "Por qué: " + why, 13, MUT)
footer()

# 6 Dependencias
slide(); title("Dependencias, supuestos y fuera de scope")
card(1.5, 3.2, 9.9, 11.2, "Dependencias", [
    "Facturación de UTEC y créditos de GCP", "Fuentes: Kaggle (oct–nov) y espejo REES46 (dic–abr)", "Red de oficina: SSH solo por IAP, gRPC bloqueado"], 18, sep="\n\n")
card(12.0, 3.2, 9.9, 11.2, "Supuestos", [
    "Inventario derivado: 50 unidades por producto y semana", "70 M eventos al mes; streaming ≈ 120 h al mes", "Precios de lista; REES46 y Olist se cruzan por categoría"], 18, hfill=S, sep="\n\n")
card(22.5, 3.2, 9.9, 11.2, "Fuera de scope", [
    "Licencia comercial y datos de producción", "Enmascaramiento dinámico (exige organización GCP)", "terraform apply y alta disponibilidad multirregión"], 18, hfill=MUT, sep="\n\n")
shp(1.5, 15.1, 30.9, 2.2, "Lo que mueve la calculadora: volumen de eventos, horas de Dataflow y precios de lista", 20, "FFFFFF", True, fill=P, preset="rect", align="center", valign="middle")
footer()

# 7 Arquitectura final
slide(); title("Arquitectura final")
for y, lab in ((2.9, "BATCH · carga histórica"), (7.7, "STREAMING · replay del pico")):
    shp(1.5, y, 18.8, 4.5, fill=LIGHT, preset="rect")
    shp(1.8, y + .05, 14, .8, lab, 11, MUT, True)
lanes = [(3.8, P, "L", [("Fuentes", "Kaggle · espejo REES46 · Olist"), ("VM efímera", "descarga, limpia y sube"), ("Cloud Storage", "zona raw versionada")]),
         (8.6, S, "R", [("Replay del pico", "script Python, 10x a 60x"), ("Pub/Sub", "rees46-events · 7 días"), ("Dataflow", "plantilla + UDF · Beam\ninválidos → deadletter")])]
for y, col, k, items in lanes:
    for i, (h_, sub) in enumerate(items):
        node(1.8 + i * 6.4, y, 5.4, 3.3, h_, sub, col, f"{k}{i}")
shp(21.2, 3.8, 5.6, 8.1, fill="2B3A4E", preset="roundRect", name="BQ")
shp(21.3, 4.1, 5.4, 1.2, "BigQuery", 19, "FFFFFF", True, "Georgia", align="center", valign="middle")
shp(21.5, 5.4, 5.0, 6.3, "bronze: events_raw\nsilver: dims y facts\ngold: agg_*, ml_*, stream_*\n\nBigQuery ML: ARIMA_PLUS\n\n06:00 refresco incremental\n07:00 chequeos ASSERT", 13, "E6EEF4", align="center")
node(27.7, 3.8, 4.6, 3.3, "API", "Cloud Run privada\n5 endpoints", A, "API")
node(27.7, 8.6, 4.6, 3.3, "Looker Studio", "7 páginas\nsolo tablas gold", A, "LK", 16)
for k in "LR":
    arrow(f"{k}0", f"{k}1"); arrow(f"{k}1", f"{k}2"); arrow(f"{k}2", "BQ")
arrow("BQ", "API"); arrow("BQ", "LK")
shp(1.5, 12.6, 20, .9, "Transversal", 15, P, True, "Georgia")
chips = ["Una cuenta de servicio por componente", "Secretos en Secret Manager", "Policy tags y row access", "Dataplex: linaje y glosario",
         "Alertas por correo", "Snapshots y simulacro de DR", "Terraform (52 recursos) y CI", "Presupuesto y teardown"]
for i, c in enumerate(chips):
    shp(1.5 + (i % 4) * 7.83, 13.6 + (i // 4) * 2.1, 7.3, 1.8, c, 14, TXT, fill=LIGHT, preset="roundRect", align="center", valign="middle")
footer()

# 6 Despliegue: scripts, Terraform y CI (observación 1 de la P2)
slide(); title("Despliegue: scripts, Terraform y CI")
table(1.5, 3.0, [10.6, 9.4, 5.2, 5.6], [("Paso de despliegue", "Qué crea", "Terraform", "CI en cada push"),
    ("1  infra/01_setup.sh", "APIs, bucket, datasets, Pub/Sub, presupuesto", "Sí, salvo presupuesto", "fmt, validate, shellcheck"),
    ("2  infra/02_iam.sh", "Cuentas de servicio, roles, secreto Kaggle", "Sí", "shellcheck"),
    ("3  monitoring/setup_alerts.sh", "Canal de correo y 3 alertas", "Sí", "JSON válido"),
    ("4  infra/03_vm.sh · ingest/bq_load.sh", "VM efímera y carga batch", "No: efímero y datos", "shellcheck"),
    ("5  infra/04_fine_grained_access.py", "Taxonomía y policy tags", "Sí", "py_compile"),
    ("6  sql/12 · infra/05_governance.sh", "Row access, linaje y glosario", "No", "shellcheck"),
    ("7  infra/06_scheduled_queries.sh", "Consultas de 06:00 y 07:00", "No", "dry run sql/14 y 15 (main)"),
    ("8  infra/07_ci_identity.sh", "Identidad del CI (WIF, sa-terraform)", "No", "lo usa el plan (main)"),
    ("9  streaming: plantilla y Beam", "Jobs de Dataflow y replays", "No: jobs efímeros", "test UDF y Beam"),
    ("10 sql/16 · sql/18", "Modelos de BigQuery ML", "No", "—"),
    ("11 infra/99_teardown.sh", "Apaga lo que cobra por hora", "—", "shellcheck")], 12, 1.05)
shp(1.5, 15.9, 30.8, 2.0, "Orden limpio: config.env → scripts 1 a 8 → terraform plan (esperado: 0 altas, 0 bajas) → CI en verde → demo → teardown. "
    "Terraform adopta 52 recursos persistentes con bloques import; plan del 19 nov: 52 importados, 0 altas, 0 bajas y 6 cambios en sitio (solo etiquetas que GCP ya tiene; el proveedor no las lee al importar). "
    "En cada push a main, el CI corre este plan con Workload Identity Federation (cuenta de solo lectura, sin llaves) y falla si quisiera crear o destruir algo.", 12, P)
footer()

# 8 Casos borde (observación 2 de la P2)
slide(); title("Casos borde: duplicados y conciliación")
card(1.5, 3.0, 10.2, 7.6, "Por qué aparecen", [
    "Pub/Sub entrega al menos una vez; la plantilla no deduplica",
    "El CSV ya trae filas repetidas: el batch las quita, el stream no"], 16, sep="\n\n")
table(12.3, 3.0, [7.6, 6.2, 6.2], [("Día del replay", "Eliminadas", "Quedan"),
    ("17/11 pico (10x)", "15 456", "6 379 921"), ("29/11 Black Friday (60x)", "3 606 (4 de Pub/Sub)", "1 850 824"),
    ("02/12 Cyber Monday (60x)", "2 634", "1 738 413"), ("Total", "21 696", "")], 13, 1.2)
shp(12.3, 9.1, 20, 1.6, "sql/14 (06:00): ROW_NUMBER() sobre todas las columnas, solo filas stream. "
    "Quedan los eventos distintos; los 4 ASSERT de sql/15 pasan.", 14, P, True)
steps = [("05 nov", "Plantilla + UDF: 3 replays, 9,99 M mensajes, 0 perdidos"), ("05 nov", "Storage Write API y deduplicación diaria"),
         ("06 nov", "Beam propio: valida, enriquece y agrega; 379 de 379 contra batch"), ("12 nov", "Relanzamiento: ventana repetida, limpieza con dedup_replay.sh"),
         ("17 → 21 nov", "Ensayo con API en Cloud Run; demo en vivo")]
shp(1.5, 11.0, 30.8, 0.9, "Evolución del pipeline de streaming", 15, P, True, "Georgia")
for i, (d, t) in enumerate(steps):
    x = 1.5 + i * 6.25
    shp(x, 12.0, 5.8, 1.2, d, 15, "FFFFFF", True, "Georgia", fill=P if i % 2 == 0 else S, align="center", valign="middle")
    shp(x, 13.2, 5.8, 4.5, t, 16, fill=LIGHT, preset="rect", align="center", valign="middle")
footer()

# 9 API
slide(); title("Capa de exposición: API sobre BigQuery")
eps = [("/ventas/diarias", "Compras e ingresos por día y categoría (agg_embudo_categoria_dia)"),
    ("/embudo/{categoria}", "Sesiones view, cart y purchase, y tasa de conversión"),
    ("/pronostico", "Serie real, pronóstico ARIMA_PLUS e intervalo, y referencia"),
    ("/pronostico/resumen", "Error del modelo frente al promedio de referencia"),
    ("/stream/minuto", "Últimos minutos agregados por el pipeline Beam"),
    ("/health", "Estado del servicio")]
for i, (path, desc) in enumerate(eps):
    yy = 3.2 + i * 1.5
    shp(1.5, yy, 30.8, 1.3, fill=LIGHT, preset="rect")
    shp(1.5, yy, .2, 1.3, fill=S, preset="rect")
    pill(2.1, yy + .25, 1.7, .8, "GET", GREEN, 12, font="Consolas")
    shp(4.1, yy, 8.4, 1.3, path, 15, P, True, "Consolas", valign="middle")
    shp(12.6, yy, 19.5, 1.3, desc, 14, TXT, valign="middle")
card(1.5, 12.9, 15, 4.9, "Diseño y seguridad", ["FastAPI en Cloud Run, cuenta sa-api con jobUser y dataViewer", "Privada: exige token de identidad; sin token, 403",
    "Consultas parametrizadas; tope de 10 GB facturados; máx. 2 instancias"], 13)
shp(17.0, 12.9, 15.3, 4.9, fill="2B3A4E", preset="rect")
shp(17.3, 13.1, 14.8, 4.5, "$ curl -H \"Authorization: Bearer $TOKEN\" $URL/embudo/electronica\n{\"view\":6343679,\"cart\":873356,\n \"purchase\":434872,\"conversion_pct\":6.86}", 13, "FFFFFF", font="Consolas")
footer()

# 10 Calculadora
slide(); title("Calculadora de consumo: año 1")
ops.append({"command": "add", "parent": f"/slide[{n}]", "type": "chart", "props": {"chartType": "bar", "series1.name": "USD por mes", "series1.values": "59.3,15.0,12.4,7.6,6.3,3.2,1.8", "series1.color": P,
            "categories": "Dataflow,Gobierno y monitoreo,BigQuery ML,Cloud Run,BigQuery consultas,BigQuery storage,GCS y Pub/Sub", "x": "1.5cm", "y": "3.1cm", "width": "14.5cm", "height": "11cm"}})
table(16.6, 3.2, [9.5, 3.4, 2.8], [("Servicio", "USD/mes", "%"), ("Dataflow streaming", "59,28", "56"), ("Gobierno y monitoreo", "15,00", "14"), ("BigQuery ML", "12,40", "12"),
    ("Cloud Run", "7,60", "7"), ("BigQuery consultas", "6,25", "6"), ("BigQuery storage", "3,15", "3"), ("Pub/Sub y GCS", "1,76", "2"), ("Total mensual", "105,45", "100")], 13, 1.3)
shp(1.5, 15.3, 31, 2.6, "Total del primer año: US$ 1 265 a precio de lista, sin capas gratuitas ni créditos. Referencia real: la facturación del 1 al 6 de nov fue S/ 8,75 bruto, cubierta por créditos. Archivo: docs/p3/calculadora_consumo.xlsx, con supuestos editables.", 15, P, True)
footer()

# 12 Demo
slide(); title("Demo end-to-end: ventas en tiempo real")
steps = ["1 Replay a Pub/Sub", "2 Dataflow procesa", "3 Escribe en BigQuery", "4 La API responde", "5 Looker muestra"]
for i, s_ in enumerate(steps):
    x = 1.5 + i * 6.3
    shp(x, 3.2, 5.6, 2.2, s_, 17, "FFFFFF", True, "Georgia", fill=P if i % 2 == 0 else S, preset="roundRect", align="center", valign="middle", name=f"D{i}")
for i in range(4):
    ops.append({"command": "add", "parent": f"/slide[{n}]", "type": "connector",
                "props": {"from": f"/slide[{n}]/shape[@name=D{i}]", "to": f"/slide[{n}]/shape[@name=D{i+1}]", "shape": "straight", "color": TXT, "tailEnd": "triangle"}})
table(1.5, 6.1, [6.6, 4.9, 4.9], [("Ensayo 17 nov", "Stream", "Batch"), ("Eventos", "227 830", "227 830"), ("Compras", "7 134", "7 134"), ("Ingresos (USD)", "2 324 635,61", "2 324 635,61"), ("Combinaciones", "379 de 379", "")], 13, 1.3)
pic("06_stream_minuto", 18.3, 6.1, 14.0, 8.75, "Tabla stream_categoria_minuto en BigQuery")
card(1.5, 12.9, 16, 5.0, "Qué se ve en vivo", ["Job de Dataflow en Running y su grafo", "Replay a 10x de 30 min del peak, 180 s, 0 fallos", "Conciliación en SQL y consulta a la API con token"], 13, hfill=S)
shp(18.3, 15.4, 14.0, 2.4, "Plan B: grabación del replay y API local si falla la red de oficina.", 14, MUT)
footer()

# 14 Conclusiones
slide(); title("Conclusiones")
tiles = [("0 de 9,99 M", "mensajes perdidos en los replays; 379 de 379 combinaciones conciliadas"),
         ("US$ 105/mes", "costo estimado del año 1 (US$\u00a01\u00a0265), dominado por Dataflow; el real fue mucho menor"),
         ("76 %", "de las compras de diciembre con categoría contradictoria: la taxonomía cambió y se corrigió por producto"),
         ("36 % vs 20 %", "error del pronóstico frente al promedio simple: falta un año de historia, y lo mostramos tal cual"),
         ("5 endpoints", "API privada en Cloud Run: IAM, consultas parametrizadas y tope de 10 GB"),
         ("52 recursos", "bajo Terraform, con tutorial y CI en el repositorio: despliegue reproducible")]
for i, (big, t) in enumerate(tiles):
    x, y = 1.5 + (i % 3) * 10.45, 3.3 + (i // 3) * 7.2
    shp(x, y, 9.9, 6.7, fill=LIGHT, preset="rect")
    shp(x, y, .25, 6.7, fill=A)
    shp(x + .6, y + .5, 9.0, 2.2, big, 34, P, True, "Georgia", valign="middle")
    shp(x + .6, y + 2.9, 9.0, 3.6, t, 17)
shp(0, 0, 0.6, 19.05, fill=A)
footer()

# 15 Next steps
slide(); title("Next Steps")
nxt = [("Licencia comercial de datos y fuente en producción", "Uso real fuera del curso", True),
    ("Reducir Dataflow: autoscaling y ventanas más cortas", "Baja el 56 % del costo", False),
    ("Reentrenar con un año de historia y XGBoost", "Supera la referencia", True),
    ("Autenticación y cuotas por cliente en la API", "Acceso a terceros", False),
    ("Aplicar Terraform y montar CI/CD de despliegue", "Reproducible sin pasos manuales", False),
    ("Enmascaramiento dinámico con una organización GCP", "Gobierno de datos completo", False)]
for i, (act, ben, prio) in enumerate(nxt):
    x, y = 1.5 + (i % 3) * 10.54, 3.3 + (i // 3) * 7.2
    shp(x, y, 9.78, 6.6, fill=LIGHT, preset="rect")
    shp(x + .5, y + .5, 1.8, 1.8, str(i + 1), 22, "FFFFFF", True, "Georgia", fill=A if prio else P, preset="ellipse", align="center", valign="middle")
    if prio:
        pill(x + 6.3, y + .9, 3.0, .9, "Prioridad", A, 12)
    shp(x + .5, y + 2.7, 8.8, 2.3, act, 18, TXT, True)
    shp(x + .5, y + 5.1, 8.8, 1.1, ben, 15, S, True)
footer()

# Separador: diapositivas de respaldo para las preguntas
slide(P)
shp(3, 7.5, 28, 3, "Respaldo para preguntas", 40, "FFFFFF", True, "Georgia", valign="middle")

# 8 Beam
slide(); title("Pipeline en tiempo real (Beam)")
flow = [("Pub/Sub", "rees46-events-beam\nsuscripción propia", P), ("Validar", "fecha, event_type,\nproduct_id, precio", S),
        ("Enriquecer", "categoría común\n(side input)", S), ("Ventana 1 min", "minuto × categoría\ntardío: 10 min", S),
        ("BigQuery", "stream_categoria_minuto\nstreaming inserts", TXT)]
for i, (h_, sub, col) in enumerate(flow):
    node(1.5 + i * 6.37, 3.2, 5.4, 3.6, h_, sub, col, f"B{i}", 16)
node(7.87, 8.0, 5.4, 2.8, "Cola de errores", "events_deadletter\ncon su motivo", A, "DL", 15)
node(14.24, 8.0, 5.4, 2.8, "Cloud Storage", "386 299 productos", MUT, "GCS", 15)
for i in range(4):
    arrow(f"B{i}", f"B{i+1}")
arrow("B1", "DL"); arrow("GCS", "B2")
shp(1.5, 8.0, 5.4, 2.8, "En paralelo al job de la plantilla, sin compartir suscripción", 13, TXT, fill=LIGHT, preset="rect", align="center", valign="middle")
shp(20.61, 8.0, 11.76, 2.8, "Ventanas por hora de llegada (marca de Pub/Sub): por hora del evento, el watermark descartaría los eventos de 2019", 14, TXT, fill=LIGHT, preset="rect", valign="middle")
for i, (big, sub, col) in enumerate([("227 830", "eventos procesados en el ensayo", P), ("379/379", "combinaciones iguales al batch, al centavo", GREEN),
                                     ("189 s", "p50 de escritura tras cerrar el minuto (1 worker, 10x)", S), ("3 de 3", "inválidos por tipo a la cola de errores", A)]):
    stat(1.5 + i * 7.91, 11.5, 7.15, 4.9, big, sub, col, 34)
shp(1.5, 16.7, 30.8, .9, "Código: streaming/beam/pipeline.py · prueba local en CI: streaming/beam/test_pipeline.py (DirectRunner)", 12, MUT)
footer()

# 11 Supuestos y escenarios
slide(); title("Calculadora: supuestos y escenarios")
table(1.5, 3.2, [12.5, 4.5], [("Supuesto", "Valor"), ("Eventos por mes", "70 M"), ("Almacenamiento inicial BigQuery", "103 GB"), ("TiB escaneados al mes", "2,0"),
    ("Horas de Dataflow al mes", "120 h"), ("Workers promedio", "1,5 × 4 vCPU"), ("Peticiones a la API al mes", "1 M"), ("Reentrenos de BQML al año", "12")], 13, 1.2)
table(19.3, 3.2, [7.3, 5.7], [("Escenario", "USD/año"), ("Base (medido)", "1 265"), ("Volumen ×3", "3 796"), ("Volumen ×10", "12 654")], 14, 1.6)
card(19.3, 10.1, 13, 7.7, "Lectura", ["Lo que más mueve el costo: horas de Dataflow", "Dentro del TiB gratuito, las consultas pesan poco", "Desde ×10, evaluar reservas de slots en BigQuery",
    "El cálculo es lineal: ignora descuentos por compromiso"], 13)
card(1.5, 13.3, 16.2, 4.6, "Costo real medido", ["Demo (carga oct–dic y 3 replays): ≈ US$ 4,35", "Consultas del proyecto: 0,75 TiB, dentro del TiB mensual gratis", "Almacenamiento: ≈ US$ 2,2 al mes"], 13, hfill=S)
footer()

# 13 Resultados
slide(); title("Resultados y hallazgos medidos")
res = [("Tráfico y streaming", P, "5,5x", "Pico real el 17/11/2019, no en Black Friday (1,6x)\n3 replays: 9 990 850 mensajes, 0 perdidos; lag máx. 7 s"),
       ("Calidad de datos", S, "21 696", "eventos repetidos eliminados\nDiciembre: 76 % de compras con categoría contradictoria, corregido por producto"),
       ("Pronóstico (honesto)", MUT, "36 % vs 20 %", "ARIMA_PLUS vs promedio simple en ene–feb; intervalo de 90 % cubre el 93,5 %\nOlist (17 meses): XGBoost 32 % vs 31 %"),
       ("Gobierno y seguridad", P, "4 de 4", "observaciones del profesor en P1: cuentas y secretos, Dataplex, cola de errores, policy tags\nAnalista restringido: sin user_id, solo ve «muebles»")]
for i, (head, col, big, t) in enumerate(res):
    x, y = 1.5 + (i % 2) * 15.8, 3.2 + (i // 2) * 7.5
    shp(x, y, 15, 7.0, fill=LIGHT, preset="rect")
    shp(x, y, 15, 1.4, head, 17, "FFFFFF", True, "Georgia", fill=col, valign="middle", align="center")
    shp(x + .5, y + 1.7, 14, 2.0, big, 36, col, True, "Georgia", valign="middle")
    shp(x + .5, y + 3.8, 14, 3.0, t, 14, TXT)
footer()

subprocess.run(["officecli", "create", OUT], check=True)
ops.append({"command": "set", "path": "/", "props": {"title": "Plataforma eCommerce en Google Cloud - Sustentación P3",
            "author": "Grupo 1 - Big Data UTEC", "lastModifiedBy": "Grupo 1 - Big Data UTEC"}})
with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
    json.dump([o for o in ops if o], f)
r = subprocess.run(["officecli", "batch", OUT, "--input", f.name], capture_output=True, text=True)
print(r.stdout[-300:], r.stderr[-600:])
