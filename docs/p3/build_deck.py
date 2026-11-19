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

def bullets(x, y, w, h, items, size=15):
    shp(x, y, w, h, "\n".join("• " + i for i in items), size)

def card(x, y, w, h, head, items, size=14, fill=LIGHT, hfill=P):
    shp(x, y, w, h, fill=fill, preset="rect")
    shp(x, y, w, 1.5, head, 17, "FFFFFF", True, "Georgia", fill=hfill, valign="middle", align="center")
    bullets(x + .3, y + 1.8, w - .6, h - 2.0, items, size)

# 1 Portada
slide(P)
shp(0, 0, 1.2, 19.05, fill=A)
shp(3, 5.2, 28, 4.2, "Plataforma eCommerce en Google Cloud", 44, "FFFFFF", True, "Georgia", valign="middle")
shp(3, 9.6, 28, 1.8, "Exposición de datos, demo end-to-end y sustentación (P3)", 24, "CADCFC")
shp(3, 13.0, 28, 1.2, "Grupo 1 · Big Data · UTEC Posgrado", 18, "FFFFFF")
shp(3, 14.4, 28, 1.2, "21 de noviembre de 2026 · Proyecto bigdata-g1-ecommerce-1105", 18, "CADCFC")

# 2 Resumen ejecutivo
slide(); title("Resumen ejecutivo y alcance")
card(1.5, 3.2, 9.9, 14.2, "Qué se implementó", [
    "Ingesta batch (Cloud Storage, bq load) y streaming (Pub/Sub, Dataflow)", "Capas bronze, silver y gold en BigQuery",
    "Pipeline Apache Beam propio: valida, enriquece y agrega por minuto y categoría", "Pronóstico de demanda con BigQuery ML",
    "Tablero de 7 páginas en Looker Studio", "API de exposición en Cloud Run (P3)", "Gobierno: Dataplex, policy tags, row access", "Operación: consultas programadas, alertas, DR, Terraform y CI"])
card(12.0, 3.2, 9.9, 14.2, "Con qué datos", [
    "REES46: 410 M eventos de navegación y compra, oct 2019 – abr 2020", "Olist: 99 470 pedidos y entregas en Brasil, 2016–2018",
    "Octubre y noviembre vienen de Kaggle; diciembre a abril, del espejo del autor", "Cruce por categoría común (18 categorías, 13 en REES46)",
    "Inventario derivado: supuesto de 50 unidades por producto y semana", "Todo se ejecutó sobre datos reales, no sintéticos"])
card(22.5, 3.2, 9.9, 14.2, "Qué entregamos en P3", [
    "Capa de exposición: 5 endpoints sobre tablas gold, con autenticación IAM", "Demo en vivo del pipeline de extremo a extremo",
    "Calculadora de consumo del primer año con escenarios ×3 y ×10", "Repositorio estructurado en GitHub con tutorial reproducible",
    "Documento de sustentación v3 (98 páginas) de la parte 2"])
footer()

# 4 KPIs
slide(); title("Criterios de éxito en formato KPI")
table(1.5, 3.2, [9.6, 5.2, 5.2, 10.8], [("Indicador", "Meta", "Medido", "Evidencia"),
    ("Pérdida de mensajes en replay", "0 %", "0 de 9 990 850", "docs/evidencia/replays.log"),
    ("Lag máximo del sistema (Dataflow)", "≤ 60 s", "7 s", "metricas_pico.csv"),
    ("Conciliación stream vs batch", "100 %", "379 de 379", "beam_conciliacion.txt"),
    ("Mensajes inválidos a la cola de errores", "100 %", "3 de 3 por tipo", "events_deadletter"),
    ("Bytes por consulta de tablero", "< 1 GB", "≈ 0,2 MB", "sql/09_bytes_scanned.sh"),
    ("Costo mensual a precio de lista", "< US$ 150", "≈ US$ 105", "calculadora_consumo.xlsx"),
    ("Intervalo de pronóstico de 90 %", "≈ 90 %", "93,5 % cubierto", "ml_resumen_pronostico"),
    ("Error del pronóstico vs promedio simple", "menor", "36 % vs 20 %", "no cumple: falta historia")], 14, 1.4)
shp(1.5, 16.3, 30.8, 1.4, "Las metas de lag, bytes y costo las fijamos para P3. El pronóstico no cumple y lo reportamos así: se necesita al menos un año de historia.", 13, MUT)
footer()

# 5 Productos
slide(); title("Productos tecnológicos a usar")
table(1.5, 3.2, [7.6, 12.2, 11], [("Producto", "Rol en la solución", "Por qué"),
    ("Cloud Storage", "Zona raw versionada, replays, lookup de Beam", "Barato y duradero; ciclo de vida"),
    ("Pub/Sub", "Cola de eventos, retención 7 días, 2 suscripciones", "Absorbe picos; entrega al menos una vez"),
    ("Dataflow + Apache Beam", "Plantilla con UDF y pipeline propio en streaming", "Autoescala de 1 a 2 workers"),
    ("BigQuery", "Almacén bronze, silver y gold; vista materializada", "Sin servidores; cobro por uso"),
    ("BigQuery ML", "ARIMA_PLUS, XGBoost y TimesFM", "Modelos en SQL, sin mover datos"),
    ("Cloud Run + FastAPI", "API de exposición, con cuenta sa-api", "Escala a cero; autenticación IAM"),
    ("Looker Studio", "7 páginas; solo lee tablas agg_* y ml_*", "Gratis; caché de 12 h"),
    ("Dataplex, Secret Manager", "Linaje, glosario, secretos", "Gobierno sin código propio"),
    ("Cloud Monitoring, Terraform, GitHub Actions", "Alertas, IaC (52 recursos), CI", "Operación reproducible")], 13, 1.4)
footer()

# 7 Arquitectura final
slide(); title("Arquitectura final")
boxes = [("Orígenes", "CSV + replay"), ("Pub/Sub", "retención 7 d"), ("Dataflow", "UDF + Beam"), ("BigQuery", "bronze → gold"), ("API · Looker", "consumo")]
w, g = 5.6, 0.7
for i, (a, b) in enumerate(boxes):
    x = 1.5 + i * (w + g)
    shp(x, 3.4, w, 3.0, f"{a}\n{b}", 18, "FFFFFF", True, "Georgia", fill=P if i % 2 == 0 else S, preset="roundRect", align="center", valign="middle", name=f"B{i}")
for i in range(4):
    ops.append({"command": "add", "parent": f"/slide[{n}]", "type": "connector",
                "props": {"from": f"/slide[{n}]/shape[@name=B{i}]", "to": f"/slide[{n}]/shape[@name=B{i+1}]", "shape": "straight", "color": TXT, "tailEnd": "triangle"}})
card(1.5, 7.2, 9.9, 10.2, "Ingesta y proceso", ["Batch: VM efímera → Cloud Storage → bq load, con deduplicación", "Streaming: replay del pico a Pub/Sub; 2 jobs en paralelo, cada uno con su suscripción",
    "Mensajes inválidos a events_deadletter", "Consultas programadas: 06:00 refresco incremental, 07:00 chequeos"], 13)
card(12.0, 7.2, 9.9, 10.2, "Almacén y consumo", ["Silver: dims, fact_eventos, fact_pedidos, fact_inventario", "Gold: agg_*, ml_*, stream_categoria_minuto",
    "BigQuery ML entrena ARIMA_PLUS por categoría", "Looker y la API leen solo gold, nunca events_raw"], 13, hfill=S)
card(22.5, 7.2, 9.9, 10.2, "Transversal", ["Una cuenta de servicio por componente", "Secretos en Secret Manager", "Policy tags y row access policies",
    "Dataplex: linaje y glosario", "Alertas por correo; snapshots y simulacro de DR", "Terraform y CI"], 13, hfill=MUT)
footer()

# 6 Despliegue: scripts, Terraform y CI (observación 1 de la P2)
slide(); title("Despliegue: scripts, Terraform y CI")
table(1.5, 3.0, [10.6, 9.4, 5.2, 5.6], [("Paso del Anexo C", "Qué crea", "Terraform", "CI en cada push"),
    ("1  infra/01_setup.sh", "APIs, bucket, datasets, Pub/Sub, presupuesto", "Sí, salvo presupuesto", "fmt, validate, shellcheck"),
    ("2  infra/02_iam.sh", "Cuentas de servicio, roles, secreto Kaggle", "Sí", "shellcheck"),
    ("3  monitoring/setup_alerts.sh", "Canal de correo y 3 alertas", "Sí", "JSON válido"),
    ("4  infra/03_vm.sh · ingest/bq_load.sh", "VM efímera y carga batch", "No: efímero y datos", "shellcheck"),
    ("5  infra/04_fine_grained_access.py", "Taxonomía y policy tags", "Sí", "py_compile"),
    ("6  sql/12 · infra/05_governance.sh", "Row access, linaje y glosario", "No", "shellcheck"),
    ("7  infra/06_scheduled_queries.sh", "Consultas de 06:00 y 07:00", "No", "dry run sql/14 y 15 *"),
    ("8  streaming: plantilla y Beam", "Jobs de Dataflow y replays", "No: jobs efímeros", "test UDF y Beam"),
    ("9  sql/16 · sql/18", "Modelos de BigQuery ML", "No", "—"),
    ("10 infra/99_teardown.sh", "Apaga lo que cobra por hora", "—", "shellcheck")], 12, 1.15)
shp(1.5, 15.9, 30.8, 2.0, "Orden limpio: config.env → scripts 1 a 7 → terraform plan (esperado: 0 altas, 0 bajas) → CI en verde → demo → teardown. "
    "Terraform adopta 52 recursos persistentes con bloques import; plan del 19 nov: 52 importados, 0 altas, 0 bajas y 6 cambios en sitio (solo etiquetas que GCP ya tiene; el proveedor no las lee al importar). "
    "* El job de plan y dry run en CI está listo y se activa con Workload Identity Federation; hoy el plan se corre local.", 12, P)
footer()

# 8 Beam
slide(); title("Pipeline en tiempo real (Beam)")
pic("06_df_grafo_beam", 1.5, 3.0, 10.4, 8.45, "Grafo del job Beam en Dataflow")
pic("06_stream_minuto", 1.5, 11.8, 10.4, 6.5, "Tabla stream_categoria_minuto en BigQuery") if False else None
bullets(12.6, 3.2, 19.7, 14.4, [
    "Lee de su propia suscripción (rees46-events-beam), en paralelo al job de la plantilla",
    "Valida: formato de fecha, event_type, product_id entero, precio no negativo",
    "Enriquece cada evento con su categoría común (side input de 386 299 productos desde Cloud Storage)",
    "Agrega por minuto y categoría en ventanas de 1 minuto con disparo a tiempo y tardío (10 min)",
    "Escribe en stream_categoria_minuto con streaming inserts (la plantilla usa Storage Write API)",
    "Inválidos van a events_deadletter con su motivo, sin detener el flujo",
    "Ventanas por hora de llegada (marca de Pub/Sub): por hora del evento, el watermark descartaría 2019",
    "Resultado: 227 830 eventos, 379 de 379 combinaciones iguales al batch, al centavo",
    "Con 1 worker y a 10x, cada minuto se escribe 3–4 min después de cerrar (p50 189 s)",
    "Prueba local en CI: streaming/beam/test_pipeline.py"], 15)
footer()

# 8 Casos borde (observación 2 de la P2)
slide(); title("Casos borde: duplicados y conciliación")
card(1.5, 3.0, 10.2, 7.6, "Por qué aparecen", [
    "Pub/Sub entrega al menos una vez y la plantilla no deduplica",
    "El CSV de origen ya trae filas repetidas: el batch las quita con SELECT DISTINCT, el stream no",
    "Repetir una ventana con la plantilla encendida la inserta dos veces"], 13)
table(12.3, 3.0, [7.6, 6.2, 6.2], [("Día del replay", "Eliminadas", "Quedan"),
    ("17/11 pico (10x)", "15 456", "6 379 921"), ("29/11 Black Friday (60x)", "3 606 (4 de Pub/Sub)", "1 850 824"),
    ("02/12 Cyber Monday (60x)", "2 634", "1 738 413"), ("Total", "21 696", "")], 13, 1.2)
shp(12.3, 9.1, 20, 1.6, "Refresco diario sql/14 (06:00): ROW_NUMBER() sobre todas las columnas, solo filas stream, en una transacción. "
    "Lo que queda coincide con los eventos distintos y pasan los 4 ASSERT de sql/15.", 12, P)
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
table(1.5, 3.2, [10, 21], [("Endpoint", "Qué devuelve"),
    ("GET /ventas/diarias", "Compras e ingresos por día y categoría (agg_embudo_categoria_dia)"),
    ("GET /embudo/{categoria}", "Sesiones view, cart y purchase, y tasa de conversión"),
    ("GET /pronostico", "Serie real, pronóstico ARIMA_PLUS e intervalo, y referencia"),
    ("GET /pronostico/resumen", "Error del modelo frente al promedio de referencia"),
    ("GET /stream/minuto", "Últimos minutos agregados por el pipeline Beam"),
    ("GET /health", "Estado del servicio")], 14, 1.35)
card(1.5, 12.9, 15, 4.9, "Diseño y seguridad", ["FastAPI en Cloud Run, cuenta sa-api con jobUser y dataViewer", "Privada: exige token de identidad; sin token, 403",
    "Consultas parametrizadas; tope de 10 GB facturados; máx. 2 instancias"], 13)
shp(17.0, 12.9, 15.3, 4.9, fill="2B3A4E", preset="rect")
shp(17.3, 13.1, 14.8, 4.5, "$ curl -H \"Authorization: Bearer $TOKEN\" $URL/embudo/electronica\n{\"view\":6343679,\"cart\":873356,\n \"purchase\":434872,\"conversion_pct\":6.86}", 13, "FFFFFF", font="Consolas")
footer()

# 12 Demo
slide(); title("Demo end-to-end en vivo")
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

# 10 Calculadora
slide(); title("Calculadora de consumo: año 1")
ops.append({"command": "add", "parent": f"/slide[{n}]", "type": "chart", "props": {"chartType": "bar", "series1.name": "USD por mes", "series1.values": "59.3,15.0,12.4,7.6,6.3,3.2,1.8", "series1.color": P,
            "categories": "Dataflow,Gobierno y monitoreo,BigQuery ML,Cloud Run,BigQuery consultas,BigQuery storage,GCS y Pub/Sub", "x": "1.5cm", "y": "3.1cm", "width": "14.5cm", "height": "11cm"}})
table(16.6, 3.2, [9.5, 3.4, 2.8], [("Servicio", "USD/mes", "%"), ("Dataflow streaming", "59,28", "56"), ("Gobierno y monitoreo", "15,00", "14"), ("BigQuery ML", "12,40", "12"),
    ("Cloud Run", "7,60", "7"), ("BigQuery consultas", "6,25", "6"), ("BigQuery storage", "3,15", "3"), ("Pub/Sub y GCS", "1,76", "2"), ("Total mensual", "105,45", "100")], 13, 1.3)
shp(1.5, 15.3, 31, 2.6, "Total del primer año: US$ 1 265 a precio de lista, sin capas gratuitas ni créditos. Referencia real: la facturación del 1 al 6 de nov fue S/ 8,75 bruto, cubierta por créditos. Archivo: docs/p3/calculadora_consumo.xlsx, con supuestos editables.", 15, P, True)
footer()

# 14 Conclusiones
slide(); title("Conclusiones")
bullets(1.5, 3.4, 30.8, 13.8, [
    "La plataforma ingiere, transforma y expone datos de eCommerce sin perder mensajes: 0 de 9,99 M y 379 de 379 combinaciones conciliadas.",
    "El costo estimado del primer año es de US$ 1 265 (≈ US$ 105 al mes), dominado por Dataflow; el real medido fue mucho menor.",
    "La calidad de datos fue el hallazgo mayor: la taxonomía de REES46 cambió desde diciembre y se corrigió por producto.",
    "El pronóstico necesita al menos un año de historia para superar al promedio simple; lo presentamos sin maquillarlo.",
    "La API en Cloud Run cumple la capa de exposición: privada, con consultas parametrizadas y tope de costo.",
    "Todo el despliegue es reproducible: tutorial paso a paso, Terraform y CI en el repositorio."], 19)
shp(0, 0, 0.6, 19.05, fill=A)
footer()

# 15 Next steps
slide(); title("Next Steps")
table(1.5, 3.4, [1.8, 17, 12], [("#", "Acción", "Beneficio"),
    ("1", "Licencia comercial de datos y fuente en producción", "Uso real fuera del curso"),
    ("2", "Reducir Dataflow: autoscaling y ventanas más cortas", "Baja el 56 % del costo"),
    ("3", "Reentrenar con un año de historia y XGBoost", "Supera la referencia"),
    ("4", "Autenticación y cuotas por cliente en la API", "Acceso a terceros"),
    ("5", "Aplicar Terraform y montar CI/CD de despliegue", "Reproducible sin pasos manuales"),
    ("6", "Enmascaramiento dinámico con una organización GCP", "Gobierno de datos completo")], 15, 1.9)
footer()

# Separador: diapositivas de respaldo para las preguntas
slide(P)
shp(3, 7.5, 28, 3, "Respaldo para preguntas", 40, "FFFFFF", True, "Georgia", valign="middle")

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

# 6 Dependencias
slide(); title("Dependencias, supuestos y fuera de scope")
card(1.5, 3.2, 9.9, 14.2, "Dependencias", [
    "Facturación de UTEC y créditos de GCP", "Espejo de REES46 (data.rees46.com) para dic–abr", "Token de Kaggle en Secret Manager para oct–nov",
    "Red de oficina con inspección SSL: SSH solo por IAP, gRPC bloqueado", "Cuenta owner en gmail, porque la organización UTEC bloquea crear proyectos"])
card(12.0, 3.2, 9.9, 14.2, "Supuestos", [
    "Inventario derivado: 50 unidades por producto, se repone cada lunes", "70 M eventos al mes durante el año 1", "Streaming en ventanas pico (≈ 120 h al mes), no 24x7",
    "Precios de lista de GCP, sin descuentos", "REES46 y Olist no son la misma tienda: el cruce es por categoría"], hfill=S)
card(22.5, 3.2, 9.9, 14.2, "Fuera de scope", [
    "Licencia comercial de los datos", "Reglas de negocio y datos de producción", "Enmascaramiento dinámico (exige organización GCP); solo hay denegación de columna",
    "Aplicar Terraform: solo plan, nunca apply", "Alta disponibilidad multirregión"], hfill=MUT)
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
card(1.5, 3.2, 15, 7.2, "Tráfico y streaming", ["Pico real el 15–17 nov 2019, no en Black Friday", "3 replays: 9 990 850 mensajes, ninguno perdido", "Dataflow escala de 1 a 2 workers, lag máximo 7 s"], 16)
card(17.3, 3.2, 15, 7.2, "Calidad de datos", ["21 696 eventos repetidos eliminados", "Diciembre trae otra taxonomía: 76 % de las compras con categoría contradictoria", "Corregido por producto; control automático de saltos > 4x"], 16, hfill=S)
card(1.5, 10.9, 15, 7.0, "Pronóstico (honesto)", ["ARIMA_PLUS: error 36 % vs 20 % del promedio simple en ene–feb", "Intervalo de 90 % cubre el 93,5 % de los días", "Olist, con 17 meses: XGBoost 32 % vs 31 % del promedio"], 16, hfill=MUT)
card(17.3, 10.9, 15, 7.0, "Gobierno y seguridad", ["Policy tags en user_id; el analista restringido solo ve «muebles»", "Cola de errores, linaje y glosario en Dataplex", "Tres alertas por correo y consultas con ASSERT"], 16)
footer()

subprocess.run(["officecli", "create", OUT], check=True)
with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
    json.dump([o for o in ops if o], f)
r = subprocess.run(["officecli", "batch", OUT, "--input", f.name], capture_output=True, text=True)
print(r.stdout[-300:], r.stderr[-600:])
