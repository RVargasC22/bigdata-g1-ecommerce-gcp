# eCommerce behavior from multi category store — Grupo 1 (Big Data, UTEC Posgrado)

Implementación en GCP del documento `Examen-grupo-1.pdf`:
Cloud Storage → Pub/Sub → Dataflow → BigQuery → Looker Studio, con Cloud Monitoring y alertas de presupuesto.

Proyecto: `bigdata-g1-ecommerce-1105` (región `us-central1`, datos en multirregión `US`).

Datos: REES46 *multi category store* (oct 2019 – mar 2020; oct–nov de Kaggle, dic–mar del espejo del autor) y
Olist (Brasil, 2016–2018).

## Estructura

```
infra/        setup del proyecto, IAM, VM de ingesta, consultas programadas, gobierno, acceso fino
ingest/       descarga a GCS (Kaggle + espejo REES46) y carga batch a BigQuery
streaming/    productor de replay (Pub/Sub), lanzamiento/drenado de Dataflow, UDF de validación
sql/          capas raw -> silver -> gold, calidad, gobierno, refresco incremental, pronóstico (BigQuery ML)
monitoring/   alertas de Cloud Monitoring y export de métricas del pico
drp/          snapshots y simulacro de recuperación
terraform/    infraestructura como código (adopta los recursos existentes con bloques import)
seed/         mapeo manual de categorías REES46 / Olist -> categoría común
docs/         correcciones al documento del examen y evidencia de las pruebas
```

## Configuración

Las cuentas personales y los IDs reales no se versionan:

```bash
cp config.env.example config.env                                   # proyecto, bucket, cuentas, facturación
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Todos los scripts leen `config.env`. `sql/run.sh` completa los placeholders `${OWNER_ACCOUNT}`,
`${ANALYST_ACCOUNT}`, etc. de `sql/15_acceso_filas.sql`, así que ese script se corre siempre con `sql/run.sh`.
El token de Kaggle vive en Secret Manager (`infra/00_iam.sh`), nunca en el repositorio.

## Mapa documento → código

| Sección del documento | Archivos |
|---|---|
| 1. Stack y capas raw / curated / analytics | `infra/01_setup.sh`, `sql/01_ddl.sql`, `sql/05_analytics.sql` |
| 2. Escalabilidad y pico | `streaming/producer.py`, `streaming/launch_dataflow.sh`, `sql/10_pico.sql`, `monitoring/export_metrics.py` |
| 3. Costos y optimización | `sql/11_costo_por_pedido.sql`, `sql/12_bytes_escaneados.sh`, `infra/lifecycle.json`, presupuesto en `infra/01_setup.sh` |
| 4. DRP / HA | `drp/snapshot.sh`, `drp/simulacro.sh`, `streaming/stop_dataflow.sh`, `monitoring/alert_system_lag.json` |
| 5. Integración multifuente | `seed/dim_categoria.csv`, `sql/03_dims.sql`, `sql/04_facts.sql`, `sql/06_fact_inventario.sql`, `sql/13_calidad.sql` |
| 7. Ingesta y storage | `ingest/download_to_gcs.sh`, `ingest/bq_load.sh`, `streaming/udf/transform.js`; ene–mar 2020: `ingest/fetch_2020.sh` + `sql/20_carga_2020.sql` |
| Seguridad: IAM y secretos | `infra/00_iam.sh` |
| Gobierno: capas, glosario, linaje | `infra/05_gobierno.sh`, `sql/14_gobierno.sql` |
| Acceso fino: columnas y filas | `infra/06_acceso_fino.py`, `sql/15_acceso_filas.sql` |
| Cola de errores (dead-letter) | `streaming/launch_dataflow.sh` (`events_deadletter`), `streaming/udf/transform.js` |
| Operación: dedup, refresco incremental, chequeos | `sql/17_incremental.sql`, `sql/18_chequeos.sql`, `infra/03_scheduled_query.sh` |
| Alertas | `monitoring/setup_alerts.sh`, `monitoring/alert_*.json` |
| IaC y CI | `terraform/`, `.github/workflows/ci.yml` |
| Pronóstico de demanda (BigQuery ML) | `sql/19_pronostico.sql` |

## Ejecución

Requisitos locales: `gcloud`/`bq` autenticados como owner del proyecto y `~/.kaggle/access_token`.

```bash
./infra/01_setup.sh                 # bucket, datasets, Pub/Sub, presupuesto
./infra/00_iam.sh                   # cuentas de servicio por componente + token de Kaggle en Secret Manager
./monitoring/setup_alerts.sh        # alertas por email: system lag, backlog Pub/Sub, scheduled query fallida
./infra/02_vm.sh                    # VM temporal de ingesta (sa-ingesta; lee el token del secreto)
gcloud compute ssh ingest-vm --zone=us-central1-a -- 'bash ~/app/ingest/download_to_gcs.sh'
./ingest/bq_load.sh                 # ruta batch: bq load + dedup + Olist + dims + facts + agregados (incluye 2020)
sql/run.sh sql/19_pronostico.sql    # pronóstico ARIMA_PLUS por categoría + validación con ene–mar 2020
./infra/03_scheduled_query.sh       # 06:00 dedup + refresco incremental (sql/17); 07:00 chequeos ASSERT (sql/18)
./infra/05_gobierno.sh              # Dataplex: linaje + glosario; capas y descripciones en sql/14_gobierno.sql
python3 infra/06_acceso_fino.py     # policy tags sobre user_id y customer_unique_id
sql/run.sh sql/15_acceso_filas.sql  # row access policies en fact_pedidos
```

`00_iam.sh` va después de `01_setup.sh` porque da permisos sobre el bucket, el tópico y la suscripción.
Los scripts de IAM los corre el owner del proyecto.

Infraestructura como código: `terraform/` describe los mismos recursos persistentes (APIs, bucket, datasets,
Pub/Sub, cuentas de servicio y permisos, secreto, taxonomía y policy tags, canal y alertas) y los adopta con
bloques `import`. `terraform plan` sobre el proyecto actual: 49 importados, 0 creados, 0 destruidos; solo reaplica etiquetas existentes
(`docs/evidencia/terraform_plan.txt`). `.github/workflows/ci.yml` valida Terraform, shell, Python, JSON y la
UDF en cada push; corre `plan` y un dry run del SQL en `main`. El `apply` queda manual.

```bash
cd terraform && terraform init && terraform plan   # apply manual, revisado por el equipo
```

Ruta streaming (simulación de Black Friday a 10x):

```bash
./streaming/launch_dataflow.sh      # esperar ~3 min a que el job esté Running
gcloud compute ssh ingest-vm --zone=us-central1-a -- \
  'source ~/app/config.env && ~/venv/bin/python ~/app/streaming/producer.py ~/data/replay/rees46_2019-11-29.csv \
     --project $PROJECT_ID --topic $TOPIC --speedup 10'
# al terminar:
gcloud compute ssh ingest-vm --zone=us-central1-a -- \
  'source ~/app/config.env && ~/venv/bin/python ~/app/monitoring/export_metrics.py --project $PROJECT_ID --hours 4' 
./streaming/stop_dataflow.sh        # drain: termina lo pendiente sin perder mensajes
```

Evidencia:

```bash
sql/run.sh sql/10_pico.sql sql/13_calidad.sql sql/11_costo_por_pedido.sql
sql/12_bytes_escaneados.sh
./drp/snapshot.sh && ./drp/simulacro.sh
```

Apagar lo que cobra por hora (VM y Dataflow): `./infra/99_teardown.sh`.

## Decisiones de implementación

- **Días en streaming.** 2019-11-29 (y 2019-12-02 si existe el archivo de diciembre) se excluyen de la carga batch y entran solo por Pub/Sub → Dataflow, así no se duplican. `events_raw.source` distingue `batch` / `stream`.
- **Validación.** El UDF (`transform.js`) rechaza `event_type` desconocidos, fechas mal formadas y precios negativos; esos mensajes van a `events_deadletter`.
- **Duplicados.** La carga batch pasa por `events_staging` (todo STRING) y se inserta con `SELECT DISTINCT`.
- **Inventario derivado.** Stock inicial fijo de 50 unidades por producto cada lunes; cada `purchase` resta una unidad; reposición semanal. `quiebre = true` cuando la demanda de la semana alcanza el stock.
- **Zonas horarias.** REES46 ya viene en UTC; Olist se convierte de `America/Sao_Paulo` a UTC.
- **Tableros.** Looker Studio lee solo tablas `agg_*`, `ml_*` y la vista materializada `mv_eventos_hora`, nunca `events_raw`.
- **Taxonomía desde diciembre.** Los archivos del espejo (dic 2019 – mar 2020) numeran `category_id` / `category_code` distinto que Kaggle: el 76 % de las compras de diciembre trae un código que contradice el del mismo producto en oct–nov (p. ej. smartphones Samsung como `construction.tools.light`). La categoría se toma por producto desde oct–nov (`dim_producto`) y `fact_eventos` la usa en lugar del código del evento. `sql/18_chequeos.sql` falla si una categoría salta más de 4x en una semana.
- **Pronóstico.** ARIMA_PLUS por categoría, entrenado solo con 2019 y validado contra ene–mar 2020 reales, que el modelo nunca vio (marzo incluye el confinamiento por COVID-19 en Rusia).

## Looker Studio (manual, ~15 min)

Reporte armado: https://lookerstudio.google.com/reporting/270afb19-8307-4db9-b5a8-4465d24330ee
(7 páginas: Pedidos e ingresos, Embudo por categoría, Demanda vs stock, Entregas y conversión, Streaming en vivo,
Calidad y gobierno, Pronóstico de demanda). Las fuentes guardan caché de 12 h: antes de presentar, ⋮ → Actualizar datos.

Atajo: abrir el enlace de `docs/looker_crear_reporte.url` (Linking API) crea el reporte con `agg_pedidos_hora` ya conectada (sin plantilla la API admite una sola fuente); las otras se agregan con "Agregar datos" (paso 2).

1. lookerstudio.google.com → Crear → Fuente de datos → BigQuery → `bigdata-g1-ecommerce-1105` → `ecommerce`.
2. Agregar fuentes: `agg_pedidos_hora`, `agg_embudo_categoria_dia`, `agg_entregas_categoria`, `agg_demanda_vs_inventario`, `agg_conversion_vs_cumplimiento`, `mv_eventos_hora`.
3. Páginas sugeridas:
   - **Pedidos e ingresos por hora:** serie temporal `hora` vs `pedidos`, `ingresos` (agg_pedidos_hora).
   - **Embudo:** barras por `categoria_comun` con `sesiones_view`, `sesiones_cart`, `sesiones_purchase`.
   - **Stock:** serie `fecha` vs `productos_en_quiebre`, `demanda_no_atendida`, con `evento` como dimensión.
   - **Entregas:** tabla `categoria_comun`, `dias_entrega_prom`, `pct_atrasados` + dispersión `tasa_conversion` vs `dias_entrega_prom`.
   - **Streaming en vivo:** `mv_eventos_hora` filtrado por `source = stream`, actualización de datos cada 1 min.

## Runbook DRP

| Escenario | Acción |
|---|---|
| Worker de Dataflow cae | Automático (Dataflow lo reemplaza). |
| Job de Dataflow cae | Alerta de system lag o de backlog Pub/Sub → `streaming/launch_dataflow.sh`; Pub/Sub retiene 7 días. |
| Tabla borrada | `bq cp ecommerce.TABLA@<epoch_ms> ecommerce.TABLA` (time travel 7 días) o `bq cp --restore ecommerce_dr.<snapshot> ecommerce.TABLA`. |
| Datos erróneos | `bq cp --force ecommerce.TABLA@<epoch_ms> ecommerce.TABLA` (conserva partición y clustering; un `CREATE OR REPLACE ... FOR SYSTEM_TIME AS OF` falla en tablas particionadas), o recargar desde `gs://…/raw` (nunca se modifica). |
| Falla regional | `streaming/stop_dataflow.sh` y `streaming/launch_dataflow.sh us-east1`; bucket y dataset son multirregión. |
