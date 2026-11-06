# Correcciones al documento (Examen-grupo-1.pdf) con resultados de la implementación

Cada punto indica la sección, el texto actual y el texto propuesto. Las cifras salen de las consultas del repo
(`sql/07_peak.sql`, `sql/09_bytes_scanned.sh`, `sql/10_quality.sql`, `drp/recovery_drill.sh`).
Las métricas de la simulación están en `docs/evidencia/` (`metricas_pico.csv`, `replays.log`, `sql_post_replay.txt`).

---

## Resumen ejecutivo y caso de estudio

**Dice:** "Usamos dos datasets públicos de Kaggle ... Limitamos su alcance a octubre, noviembre y diciembre de 2019".

**Problema:** el dataset de Kaggle solo trae octubre y noviembre de 2019. Diciembre no está en Kaggle.

**Debe decir:** "Limitamos su alcance a octubre, noviembre y diciembre de 2019. Octubre y noviembre se obtienen de
Kaggle; diciembre, del repositorio público del autor del dataset (data.rees46.com), con el mismo esquema.
Tras eliminar duplicados quedan 175,8 millones de eventos."

**Dice:** "La plataforma tolera picos de tráfico como Black Friday y Cyber Monday".

**Debe decir:** "La plataforma tolera picos de tráfico de varias veces un día normal. En este dataset el pico
real no es Black Friday sino la campaña del 15 al 17 de noviembre de 2019 (unos 4,3 veces el volumen de un día
normal); Black Friday y Cyber Monday tienen un volumen similar al de un día normal."

---

## 2. Escalabilidad y performance

**Dice (Cómo se demuestra, punto 1):** "Calcular el factor de pico comparando eventos por minuto del 29/11/2019
(Black Friday) y del 02/12/2019 (Cyber Monday) contra un día normal de noviembre."

**Debe decir:** "Calcular el factor de pico de cada día contra la mediana por minuto de un día normal
(1 al 20 de noviembre). Resultado:

| Día | Eventos del día | Factor (minuto máximo / p50 normal) |
|---|---|---|
| Día normal de noviembre | 1,5 a 2 millones | 1,0 (p50 = 1 521 eventos/min) |
| 15/11/2019 | 6,2 a 6,5 millones | 4,6 (máximo 6 936 eventos/min) |
| 16/11/2019 | 6,5 millones | 4,9 (máximo 7 524 eventos/min) |
| 17/11/2019 | 6,4 millones | 5,5 (máximo 8 415 eventos/min) |
| 29/11/2019 Black Friday | 1,85 millones | 1,6 (máximo 2 368 eventos/min) |
| 02/12/2019 Cyber Monday | 1,74 millones | 1,4 (máximo 2 091 eventos/min) |

El 15/11 no registra compras en el dataset (hueco de datos), por eso el día pico simulado es el 17/11."

**Dice (punto 2):** "Reproducir los eventos de ese día ... acelerando el ritmo (por ejemplo 10x)".

**Debe decir:** "Se reprodujeron tres días por Pub/Sub → Dataflow → BigQuery: el 17/11 (día pico, 6,4 millones de
eventos) a 10x, y Black Friday y Cyber Monday a 60x (unos 1 250 eventos por segundo). No se perdió ningún
mensaje: 0 fallos de publicación, 0 filas en la tabla de errores, y en BigQuery quedaron 6 395 377 eventos
del 17/11 (los mismos publicados), 1 741 047 del 02/12 y 1 854 430 del 29/11 (4 más que los publicados:
duplicados por la entrega al-menos-una-vez de Pub/Sub)."

**Agregar (resultados medidos):**

| Indicador | Resultado |
|---|---|
| Eventos/s publicados (promedio del día) | 10x: 740 ev/s; 60x: 1 209 a 1 288 ev/s; minuto máximo 2 227 ev/s |
| Workers de Dataflow (máx. 3) | Autoescalado de 1 a 2 workers (2 a 4 vCPU) a los 12 min del primer replay; nunca hizo falta el tercero |
| System lag máximo y tiempo de recuperación | Máximo 7 s (p50 1 s, p95 5 s). El backlog llegó a 10 066 mensajes durante 1 minuto y bajó a ~1 100 en el minuto siguiente |
| Bytes escaneados, SELECT * | 21 947 MB |
| Bytes escaneados, 3 columnas | 6 724 MB |
| Bytes escaneados, 3 columnas + filtro por event_type (clustering) | 568 MB |
| Bytes escaneados, 3 columnas + filtro de un día (partición) | 20,9 MB |
| Bytes escaneados, tabla agregada del tablero | 0,1 MB |
| Latencia de consulta del tablero (sin caché, tablas agg_*) | 0,17 a 0,25 s, menos de 0,1 MB escaneados |

---

## 3. Costos

**Dice:** "BigQuery, consultas on-demand ... 2.087 USD/TiB ... 3.13".

**Problema:** el precio de lista on-demand es 6,25 USD/TiB con el primer TiB mensual gratis. El total de 3,13 USD
es correcto (0,5 TiB facturables × 6,25), pero el precio unitario no.

**Debe decir:** "6,25 USD/TiB (primer TiB del mes gratis)".

**Dice:** "Cloud Storage (Standard) 0,016 USD/GB-mes" y "BigQuery almacenamiento activo 0,014 USD/GB-mes".

**Debe decir:** precios de la multirregión US, que es la que se usa: Cloud Storage Standard 0,026 USD/GB-mes;
BigQuery almacenamiento lógico activo 0,02 USD/GB-mes con los primeros 10 GB gratis. Verificar en la calculadora.

**Agregar al escenario base:** dos costos que no estaban:
- Streaming Engine de Dataflow (se cobra aparte de vCPU y memoria).
- Escritura en streaming a BigQuery (la plantilla usa inserciones en streaming, 0,01 USD por 200 MB con mínimo
  de 1 KB por fila).

**Agregar (costo real de la demostración):**

| Concepto | Real |
|---|---|
| Consultas BigQuery (86 jobs) | 0,164 TiB facturados, dentro del TiB gratis |
| Dataflow (job streaming ~3,8 h) | ~1,05 USD a precio de lista (8,9 vCPU-h, 33 GB-h de memoria, 3,46 SECU-h de Streaming Engine; métricas del job) |
| VM de ingesta temporal | ~0,66 USD (e2-standard-4 por ~4,5 h y disco de 200 GB) |
| Pub/Sub | ~7 GB, dentro de los 10 GiB gratis |
| Almacenamiento después de la demo | < 1 USD/mes (45 GB en BigQuery, 7,2 GB en Cloud Storage) |
| Costo por pedido | 4,35 USD / 2 372 739 pedidos = 0,0018 USD por 1 000 pedidos (sin contar la VM temporal; consultas a precio de lista aunque caen en el TiB gratis) |
| Todo el proyecto a la fecha (desarrollo, carga ene–abr 2020, pronósticos) | 1 029 consultas, 0,65 TiB facturados en consultas (`INFORMATION_SCHEMA.JOBS_BY_PROJECT`, sin contar dos veces los scripts padre): dentro del TiB gratis del mes, ~4 USD a precio de lista. Con Dataflow (~1,05) y las VMs de ingesta (~0,75): ~2 USD, como máximo ~6 USD. Aparte, el `CREATE MODEL` de XGBoost (`sql/18`) facturó 50,9 GB con la tarifa de BigQuery ML; su costo exacto queda por confirmar en el reporte de facturación |

**Nota:** el costo de la VM de ingesta (descarga y reproducción) no estaba en el documento; agregarla como
componente temporal que se elimina al terminar (`infra/99_teardown.sh`).

---

## 4. DRP/HA

**Dice (BigQuery, recuperación):** "Consulta con FOR SYSTEM_TIME AS OF o restauración desde un snapshot".

**Problema:** `CREATE OR REPLACE TABLE ... FOR SYSTEM_TIME AS OF` falla sobre tablas particionadas
("Cannot replace a table with a different partitioning spec").

**Debe decir:** "Copia con decorador de tiempo (`bq cp --force tabla@<epoch_ms> tabla`), que conserva partición y
clustering, o restauración desde un snapshot (`bq cp --restore`)."

**Agregar (simulacro medido sobre una copia de fact_pedidos, 99 470 filas):**

| Escenario | Método | Filas recuperadas | Tiempo |
|---|---|---|---|
| Tabla borrada | Time travel (`bq cp tabla@ms`) | 99 470 / 99 470 | 6 a 7 s |
| Borrado parcial (datos erróneos) | Time travel con `--force` | 99 470 / 99 470 | 6 a 7 s |
| Tabla borrada | Snapshot en `ecommerce_dr` | 99 470 / 99 470 | 6 a 7 s |

Con esto el RTO real de las tablas es de segundos, muy por debajo del objetivo de 1 hora.

---

## 5. Integración multifuente

**Agregar (calidad de datos medida):**
- Duplicados: la carga batch eliminó unas 236 000 filas duplicadas o inválidas con `SELECT DISTINCT`.
- El día 17/11 trae unos 15 000 duplicados que el streaming no elimina (la plantilla no deduplica).
- Categorías de Olist sin pareja en `dim_categoria`: housewares (5 884 pedidos), cool_stuff (3 632),
  perfumery (3 162) y otras.
- 56 669 productos de REES46 no tienen `category_code`.

**Agregar (cola de errores / dead-letter):** el job de Dataflow escribe los mensajes que el UDF rechaza en
`ecommerce.events_deadletter` (mensaje original, error y fecha) sin detener el flujo. Prueba: se publicaron
tres mensajes defectuosos durante la simulación (texto que no es JSON, `event_type` desconocido y precio
negativo); los tres llegaron a la tabla de errores en menos de un minuto con su causa, y el resto del streaming
siguió entrando a `events_raw`. Pub/Sub retiene 7 días, por lo que los mensajes corregidos pueden
re-publicarse.

---

## 7. Ingesta y storage

**Dice (Volumen):** "Unos 25 GB para octubre a diciembre de 2019 ... el dataset completo tiene 285 millones de
eventos según su ficha de Kaggle".

**Debe decir:** "Unos 22 GB sin comprimir (7,06 GiB comprimidos en Cloud Storage) y 175,8 millones de eventos
de octubre a diciembre de 2019 tras eliminar duplicados; en BigQuery ocupan unos 45 GB lógicos incluyendo
tablas derivadas. Olist suma unos 100 000 pedidos (120 MB)."

**Dice (Velocidad):** "Decenas de eventos por segundo en promedio".

**Debe decir:** "Unos 20 eventos por segundo en un día normal y hasta 116 eventos por segundo en el minuto
más cargado del pico (15/11). La simulación llegó a unos 1 250 eventos por segundo (60x)."

**Dice (REES46, eventos en vivo):** "con un factor de aceleración (por ejemplo 10x)".

**Debe decir:** "con un factor de aceleración de 10x para el día pico (17/11) y 60x para Black Friday y Cyber
Monday".

---

## Agregar: componentes transversales (retroalimentación del docente)

### 1. Identidades y secretos (IAM y Secret Manager)

La primera corrida usó la cuenta de servicio por defecto de Compute Engine (rol Editor del proyecto) y el
token de Kaggle se copiaba a la VM. Ahora cada componente tiene su propia cuenta con el mínimo privilegio
(`infra/02_iam.sh`):

| Cuenta de servicio | Componente | Permisos |
|---|---|---|
| `sa-ingesta` | VM de descarga y productor de replay | Escribir en el bucket del proyecto, publicar en el tópico `rees46-events`, leer el secreto `kaggle-token`, leer métricas de Monitoring |
| `sa-dataflow` | Workers de Dataflow | `dataflow.worker`, consumir la suscripción, escribir solo en el dataset `ecommerce`, staging en el bucket |
| `sa-transform` | Consulta programada diaria | Ejecutar consultas (`bigquery.jobUser`) y escribir solo en el dataset `ecommerce` |

El token de Kaggle vive en Secret Manager (`kaggle-token`); la VM lo lee al arrancar y ya no se copia desde
una laptop ni aparece en el repositorio. Pruebas (`docs/evidencia/cuentas_servicio.txt`): una VM con
`sa-ingesta` leyó el secreto, publicó en el tópico y listó el bucket, y recibió "acceso denegado" al consultar
BigQuery o crear un tópico; un job de Dataflow con workers `sa-dataflow` escribió un evento válido en
`events_raw` y dos inválidos en `events_deadletter`; la consulta programada se ejecutó como `sa-transform` y
reconstruyó `fact_inventario`, las tablas `agg_*` y los metadatos sin errores.

### 2. Gobierno, linaje y calidad (Dataplex Universal Catalog)

- **Capas y metadatos:** cada tabla lleva la etiqueta `capa` = `bronze` (datos tal como llegan: `events_raw`,
  `events_deadletter`, `olist_*`), `silver` (modelo integrado: `dim_*`, `fact_*`) o `gold` (tablas de los
  tableros: `agg_*`, `mv_eventos_hora`), más la etiqueta `fuente` y descripciones de tablas y columnas clave
  (`sql/11_governance.sql`). Dataplex las cataloga automáticamente y se pueden buscar por `labels.capa=gold`.
- **Glosario de negocio:** `glosario-ecommerce` en Dataplex con 10 términos que fijan cómo se calcula cada
  indicador: evento, sesión, pedido, embudo de conversión, tasa de conversión, categoría común, tiempo de
  entrega, quiebre de stock, factor de pico y dato personal (`infra/05_governance.sh`). Las descripciones de las
  columnas citan el término del glosario.
- **Linaje:** con la Data Lineage API activa, cada consulta de BigQuery registra sus tablas de origen y
  destino. Verificado con la API de linaje: `events_raw` + `dim_categoria` -> `dim_producto`,
  `events_raw` -> `fact_inventario`, `events_raw` -> `agg_pedidos_hora` y `fact_eventos` (vista sobre
  `events_raw`) -> `agg_embudo_categoria_dia`. Se ve en BigQuery (pestaña Linaje de cada tabla) y permite seguir un clic crudo
  hasta la métrica de la capa gold.
- **Calidad:** `sql/10_quality.sql` (duplicados, categorías sin pareja, eventos por fuente) y la tabla de
  errores del streaming (sección 5).

### 3. Cola de errores (dead-letter)

Ver la sección 5: `events_deadletter` aísla los mensajes defectuosos sin detener el flujo; probado con tres
mensajes malformados.

### 4. Control de acceso fino en BigQuery

- **Columnas (policy tags):** taxonomía `datos-personales` con dos policy tags, `identificador_usuario`
  sobre `events_raw.user_id` e `identificador_cliente` sobre `olist_customers.customer_unique_id`
  (`infra/04_fine_grained_access.py`). Solo el propietario y el equipo (`Fine-Grained Reader`) pueden leer esas
  columnas; el analista de ejemplo recibe "acceso denegado" si las pide, pero consulta el resto de la tabla.
  El enmascaramiento dinámico (SHA-256 para analistas) usa *data policies*, que exigen que el proyecto
  pertenezca a una organización de Google Cloud; este proyecto se creó con una cuenta personal (la
  organización de UTEC no permite crear proyectos), así que queda como siguiente paso en un entorno con
  organización.
- **Filas (row access policies):** en `fact_pedidos`, el propietario, el equipo y `sa-transform` ven todas las
  filas; el analista de ejemplo solo ve la categoría `muebles` (`sql/12_row_access.sql`).

### 5. Operación según buenas prácticas

- **Escritura y deduplicación del streaming.** Dataflow escribe con la Storage Write API
  (`useStorageWriteApi=true`) en lugar de los *streaming inserts* antiguos: las filas recién llegadas
  admiten `UPDATE`/`DELETE` de inmediato (probado: una fila de prueba se borró segundos después de llegar).
  Pub/Sub entrega al menos una vez y el CSV de origen trae filas repetidas, así que el refresco diario
  (`sql/14_incremental.sql`) deja una sola copia de cada evento idéntico del streaming dentro de una
  transacción. Resultado: se eliminaron 21 696 filas repetidas (17/11: 15 456; 29/11: 3 606, de ellas 4 por
  reentrega de Pub/Sub; 02/12: 2 634). Filas finales: 6 379 921, 1 850 824 y 1 738 413, igual al conteo de
  eventos distintos. Después del dedup, los cuatro `ASSERT` de `sql/15_checks.sql` pasan y las dos
  consultas programadas corren como `sa-transform` sin error.
- **Refresco incremental.** La consulta programada diaria ya no reconstruye todo (`CREATE OR REPLACE` sobre
  ~9 GB de `events_raw`): lee los metadatos de particiones, toma solo los días modificados en las últimas
  26 h y hace `DELETE` + `INSERT` de esos días en `fact_inventario` (semanas completas) y en los agregados.
  Sin datos nuevos escanea casi nada. El DML conserva descripciones, etiquetas y row access policies.
- **Mínimo privilegio también en la cuenta por defecto.** Se quitó el rol Editor a la cuenta de servicio
  por defecto de Compute Engine (`infra/02_iam.sh`); nada la usa ya.
- **Alertas.** Además del system lag: (a) frescura, si un mensaje lleva más de 10 min sin procesarse en la
  suscripción (job caído o atascado); (b) cualquier fallo de una consulta programada, incluida
  `sql/15_checks.sql`, que corre a las 07:00 con `ASSERT`: más de 1 000 rechazos en el dead-letter en 24 h,
  agregados que no cuadran con `events_raw`, claves nulas o duplicados del streaming sin limpiar.
- **Infraestructura como código y CI.** `terraform/` describe los recursos persistentes y los adopta con
  bloques `import` (`terraform plan`: 49 importados, 0 creados, 0 destruidos; solo reaplica etiquetas existentes). Quedan fuera, a propósito: las tablas
  (las crea la capa SQL), el job de Dataflow y la VM (efímeros), el valor del secreto (no debe quedar en el
  estado de Terraform), el presupuesto y el glosario. `.github/workflows/ci.yml` valida Terraform, shell,
  Python, JSON y la UDF de Dataflow en cada push, y en `main` corre `terraform plan` y un dry run del SQL
  con Workload Identity Federation (sin llaves). El `apply` queda manual y revisado.

### 6. Pronóstico de demanda (BigQuery ML)

- **Datos de validación.** Para medir el pronóstico con datos que el modelo nunca vio se cargaron enero a
  abril de 2020 del mismo espejo (55,8 M, 54,6 M, 56,2 M y 66,5 M eventos; 0,83 M, 1,05 M, 1,02 M y 0,97 M
  compras). El dataset público termina en abril 2020 (mayo en adelante no existe en el espejo). La descarga
  corre en una VM efímera que se borra sola a los 30 min (`ingest/fetch_2020.sh`) y la carga en
  `sql/17_load_2020.sql`. En total, `events_raw` queda con 410 M eventos (oct 2019 – abr 2020).
- **Preparación de la serie.**
  - Taxonomía: los productos que aparecen recién desde diciembre (2,2 % de las compras de diciembre, 16 % en
    marzo, 22 % en abril) no tienen categoría de oct–nov. `dim_producto` los clasifica con un puente: cada `category_id`
    nuevo toma la categoría de oct–nov de la mayoría de sus productos compartidos, si son al menos 5 y el 80 %
    coincide (977 ids con al menos 5 productos compartidos, acuerdo medio 94 %; 862 pasan el 80 %).
  - Días incompletos: el 14–15 nov 2019, el 1–2 ene y el 20–21 abr 2020 el origen dejó de registrar compras mientras la
    navegación seguía. Se detectan solos (compras/eventos < 60 % de la mediana, vista
    `v_dias_compras_incompletas`) y se excluyen del entrenamiento y de la evaluación.
  - Dos chequeos nuevos en `sql/15_checks.sql`: una categoría que se multiplica o divide por más de 4 en una
    semana (habría detectado el salto de diciembre) y una proporción de compras sin categoría mayor al 35 %.
- **Modelo.** ARIMA_PLUS con una serie diaria de compras por categoría (las 8 con al menos 100 compras al día),
  entrenado solo hasta el 31 dic 2019, horizonte de 121 días e intervalo de 90 %. Cada error se compara con una
  referencia ingenua: el promedio diario oct–dic 2019 de cada categoría, constante.
- **Resultado (WAPE, todas las categorías).**

  | Tramo | ARIMA_PLUS | Referencia (promedio) |
  |---|---|---|
  | 1–14 ene (dos semanas) | 44,5 % | 11,4 % |
  | ene–feb | 36,1 % | 19,9 % |
  | marzo (confinamiento COVID-19) | 35,3 % | 26,2 % |
  | abril (confinamiento COVID-19) | 39,2 % | 21,3 % |

  En ene–feb, ARIMA gana en muebles, ropa y automotriz, y pierde en electrónica, cómputo, construcción,
  electrodomésticos y niños. El intervalo de 90 % contiene el 93,5 % de los días reales: está bien calibrado.
- **Lectura.** Con tres meses de historia ARIMA no supera al promedio: proyecta hacia 2020 el nivel alto de
  diciembre (sesgo positivo) y no puede aprender la estacionalidad anual (campañas de noviembre, Año Nuevo).
  Hace falta al menos un año de historia. Hasta entonces el promedio es la referencia que cualquier modelo
  debe superar, y el intervalo de ARIMA sirve para dimensionar el stock de seguridad.
- **Experimento de control con Olist (`sql/18_forecast_olist.sql`).** Para separar "falta historia" de "falta
  modelo" se repitió la prueba con Olist, que tiene 17 meses antes del corte (ene 2017 – may 2018, con un Black
  Friday). Series: pedidos diarios de las 6 categorías con al menos 15 pedidos al día más el total. Prueba:
  1 jun – 22 ago 2018 (los días siguientes están incompletos en el dataset público). Cinco métodos:
  - ARIMA_PLUS con 17 meses y con 3 meses (la misma historia que REES46), con feriados de Brasil.
  - XGBoost (`BOOSTED_TREE_REGRESSOR`) directo a 1–83 días: orígenes semanales desde abril 2017, objetivo =
    pedidos / promedio de los 28 días previos al origen, variables de serie, horizonte, día de semana, día del
    mes, feriado y perfil del día de semana de las 8 semanas previas. No extrapola tendencias.
  - TimesFM (`AI.FORECAST`), modelo preentrenado de Google sin entrenamiento propio, con los 17 meses.
  - Promedio diario de mar–may 2018 de cada serie, constante.

  | Tramo (WAPE, categorías) | ARIMA 17 m | ARIMA 3 m | XGBoost | TimesFM | Promedio 3 m |
  |---|---|---|---|---|---|
  | 1–14 jun | 42,7 % | 32,5 % | 29,0 % | 40,9 % | 27,2 % |
  | jun–jul | 43,4 % | 35,6 % | 31,9 % | 42,2 % | 30,9 % |
  | 1–22 ago | 51,7 % | 44,7 % | 24,4 % | 51,2 % | 27,6 % |

  - Más historia empeora a ARIMA: con 17 meses pronostica 111 pedidos/día en la serie total contra 203 reales;
    con 3 meses, 206. TimesFM falla igual (100). Ambos pesan mucho la última semana antes del corte, que fue
    anormalmente baja (99–144 pedidos/día del 24 al 31 may 2018, coincide con el paro de camioneros en
    Brasil), y además ARIMA arrastra el crecimiento de 2017.
  - XGBoost es el único método que iguala al promedio: empata en jun–jul y gana en agosto (24,4 % contra
    27,6 %). En la serie total, ARIMA con 3 meses es el mejor (19,1 % contra 22,7 % del promedio).
  - Lectura: el problema no es solo el modelo. Sin dos años de datos ningún método aprende la estacionalidad
    anual, y un corte que cae en una anomalía castiga a los modelos que siguen el nivel reciente. Un modelo de
    árboles con variables relativas al nivel es la alternativa más robusta, pero apenas iguala a la referencia.
  - Costo: ARIMA y TimesFM leen MB. XGBoost se entrena fuera del motor de consultas y facturó 50,9 GB con la
    tarifa de BigQuery ML (unos 18 min); no admite `--dry_run`, por lo que el script no debe reentrenarlo sin
    necesidad.
- **Costo.** Entrenar y evaluar lee solo la tabla gold `agg_embudo_categoria_dia` (KB). Con seis meses de
  datos, reconstruir silver y gold desde cero factura unos 67 GB (unos 0,41 USD a precio de lista), por lo que
  el tope por script de `sql/run.sh` (`MAX_BYTES_BILLED`) se subió de 50 GB a 100 GB.
