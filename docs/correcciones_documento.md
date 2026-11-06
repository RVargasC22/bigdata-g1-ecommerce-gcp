# Correcciones al documento (Examen-grupo-1.pdf) con resultados de la implementación

Para cada punto indicamos la sección, el texto actual del documento y el texto que proponemos en su lugar. Las
cifras salen de las consultas del repositorio (`sql/07_peak.sql`, `sql/09_bytes_scanned.sh`,
`sql/10_quality.sql` y `drp/recovery_drill.sh`), y las métricas de la simulación están en `docs/evidencia/`
(`metricas_pico.csv`, `replays.log` y `sql_post_replay.txt`).

---

## Resumen ejecutivo y caso de estudio

**Dice:** "Usamos dos datasets públicos de Kaggle ... Limitamos su alcance a octubre, noviembre y diciembre de 2019".

**Problema:** el dataset de Kaggle solo incluye octubre y noviembre de 2019. Diciembre no está disponible ahí.

**Debe decir:** "Limitamos su alcance a octubre, noviembre y diciembre de 2019. Octubre y noviembre se obtienen de
Kaggle, y diciembre, del repositorio público del autor del dataset (data.rees46.com), que usa el mismo esquema.
Después de eliminar duplicados quedan 177,3 millones de eventos."

**Dice:** "La plataforma tolera picos de tráfico como Black Friday y Cyber Monday".

**Debe decir:** "La plataforma tolera picos de tráfico de varias veces el de un día normal. En este dataset el
pico real no es Black Friday, sino la campaña del 15 al 17 de noviembre de 2019, con unas 4,3 veces el volumen de
un día normal. Black Friday y Cyber Monday tienen un volumen parecido al de cualquier otro día."

---

## 2. Escalabilidad y performance

**Dice (Cómo se demuestra, punto 1):** "Calcular el factor de pico comparando eventos por minuto del 29/11/2019
(Black Friday) y del 02/12/2019 (Cyber Monday) contra un día normal de noviembre."

**Debe decir:** "Calcular el factor de pico de cada día respecto a la mediana de eventos por minuto de un día
normal, tomando como referencia del 1 al 20 de noviembre. El resultado es el siguiente:

| Día | Eventos del día | Factor (minuto máximo / p50 normal) |
|---|---|---|
| Día normal de noviembre | 1,5 a 2 millones | 1,0 (p50 = 1 521 eventos/min) |
| 15/11/2019 | 6,2 millones | 4,6 (máximo 6 936 eventos/min) |
| 16/11/2019 | 6,5 millones | 4,9 (máximo 7 524 eventos/min) |
| 17/11/2019 | 6,4 millones | 5,5 (máximo 8 400 eventos/min) |
| 29/11/2019 Black Friday | 1,85 millones | 1,6 (máximo 2 368 eventos/min) |
| 02/12/2019 Cyber Monday | 1,74 millones | 1,4 (máximo 2 088 eventos/min) |

El 15/11 no tiene compras registradas en el dataset, lo que indica un hueco en los datos. Por eso el día pico que
se simula es el 17/11."

**Dice (punto 2):** "Reproducir los eventos de ese día ... acelerando el ritmo (por ejemplo 10x)".

**Debe decir:** "Se reprodujeron tres días a través de Pub/Sub y Dataflow hasta BigQuery. El 17/11, que es el día
pico, con 6,4 millones de eventos, se reprodujo a 10x, y Black Friday y Cyber Monday a 60x (unos 1 250 eventos
por segundo). No se perdió ningún mensaje. No hubo fallos de publicación ni filas en la tabla de errores, y en
BigQuery quedaron 6 395 377 eventos del 17/11, los mismos que se publicaron, 1 741 047 del 02/12 y 1 854 430 del
29/11. En este último caso hay 4 eventos más que los publicados, que son duplicados por la entrega al menos una
vez de Pub/Sub."

**Agregar (resultados medidos):**

| Indicador | Resultado |
|---|---|
| Eventos/s publicados (promedio del día) | 10x: 740 ev/s; 60x: 1 209 a 1 288 ev/s; minuto máximo 2 227 ev/s |
| Workers de Dataflow (máx. 3) | Autoescalado de 1 a 2 workers (2 a 4 vCPU) a los 12 min del primer replay; nunca hizo falta el tercero |
| System lag máximo y tiempo de recuperación | Máximo 7 s (p50 1 s, p95 5 s). El backlog llegó a 10 066 mensajes durante 1 minuto y bajó a ~1 100 en el minuto siguiente |
| Bytes escaneados, SELECT * | 52 668 MB |
| Bytes escaneados, 3 columnas | 16 707 MB |
| Bytes escaneados, 3 columnas + filtro por event_type (clustering) | 1 822 MB |
| Bytes escaneados, 3 columnas + filtro de un día (partición) | 9,6 MB |
| Bytes escaneados, tabla agregada del tablero | 0,2 MB |
| Latencia de consulta del tablero (sin caché, tablas agg_*) | 0,17 a 0,25 s, menos de 0,1 MB escaneados |

---

## 3. Costos

**Dice:** "BigQuery, consultas on-demand ... 2.087 USD/TiB ... 3.13".

**Problema:** el precio de lista on-demand es 6,25 USD/TiB, con el primer TiB de cada mes gratis. El total de
3,13 USD sí es correcto (0,5 TiB facturables × 6,25), pero el precio unitario no.

**Debe decir:** "6,25 USD/TiB (primer TiB del mes gratis)".

**Dice:** "Cloud Storage (Standard) 0,016 USD/GB-mes" y "BigQuery almacenamiento activo 0,014 USD/GB-mes".

**Debe decir:** deben usarse los precios de la multirregión US, que es donde está el proyecto. Cloud Storage
Standard cuesta 0,026 USD/GB-mes, y el almacenamiento lógico activo de BigQuery, 0,02 USD/GB-mes con los primeros
10 GB gratis. Conviene verificarlo en la calculadora.

**Agregar al escenario base:** faltaban dos costos.
- El Streaming Engine de Dataflow, que se cobra aparte de la vCPU y la memoria.
- La escritura en streaming a BigQuery. La plantilla usa inserciones en streaming, que cuestan 0,01 USD por cada
  200 MB, con un mínimo de 1 KB por fila.

**Agregar (costo real de la demostración):**

| Concepto | Real |
|---|---|
| Consultas BigQuery (86 jobs) | 0,164 TiB facturados, dentro del TiB gratis |
| Dataflow (job streaming ~3,8 h) | ~1,05 USD a precio de lista (8,9 vCPU-h, 33 GB-h de memoria, 3,46 SECU-h de Streaming Engine; métricas del job) |
| VM de ingesta temporal | ~0,66 USD (e2-standard-4 por ~4,5 h y disco de 200 GB) |
| Pub/Sub | ~7 GB, dentro de los 10 GiB gratis |
| Almacenamiento después de la demo | < 1 USD/mes (45 GB en BigQuery, 7,2 GB en Cloud Storage) |
| Almacenamiento al 6 nov 2026, con ene–abr 2020 | ~2,2 USD/mes (103 GB lógicos en BigQuery, de ellos 25,5 GB en `events_staging` y 22,2 GB en el snapshot de `ecommerce_dr`; 19,6 GB en Cloud Storage) |
| Costo por pedido | 4,35 USD / 2 372 739 pedidos = 0,0018 USD por 1 000 pedidos (sin contar la VM temporal; consultas a precio de lista aunque caen en el TiB gratis) |
| Todo el proyecto a la fecha (desarrollo, carga ene–abr 2020, pronósticos) | 1 143 consultas, 0,75 TiB facturados en consultas (`INFORMATION_SCHEMA.JOBS_BY_PROJECT`, sin contar dos veces los scripts padre): dentro del TiB gratis del mes, ~4,7 USD a precio de lista. Con Dataflow (~1,05) y las VMs de ingesta (~0,75): ~2 USD, como máximo ~6,5 USD. Aparte, el `CREATE MODEL` de XGBoost (`sql/18`) facturó 50,8 GB con la tarifa de BigQuery ML; su costo exacto queda por confirmar en el reporte de facturación |

**Nota:** el documento no incluía el costo de la VM de ingesta, que descarga y reproduce los datos. Hay que
agregarla como un componente temporal que se elimina al terminar (`infra/99_teardown.sh`).

---

## 4. DRP/HA

**Dice (BigQuery, recuperación):** "Consulta con FOR SYSTEM_TIME AS OF o restauración desde un snapshot".

**Problema:** `CREATE OR REPLACE TABLE ... FOR SYSTEM_TIME AS OF` falla en tablas particionadas, con el error
"Cannot replace a table with a different partitioning spec".

**Debe decir:** "Copia con decorador de tiempo (`bq cp --force tabla@<epoch_ms> tabla`), que conserva la partición
y el clustering, o restauración desde un snapshot (`bq cp --restore`)."

**Agregar (simulacro medido sobre una copia de fact_pedidos, 99 470 filas):**

| Escenario | Método | Filas recuperadas | Tiempo |
|---|---|---|---|
| Tabla borrada | Time travel (`bq cp tabla@ms`) | 99 470 / 99 470 | 6 a 7 s |
| Borrado parcial (datos erróneos) | Time travel con `--force` | 99 470 / 99 470 | 6 a 7 s |
| Tabla borrada | Snapshot en `ecommerce_dr` | 99 470 / 99 470 | 6 a 7 s |

En la práctica, recuperar una tabla toma segundos, muy por debajo del objetivo de 1 hora.

---

## 5. Integración multifuente

**Agregar (calidad de datos medida):**
- Duplicados: la carga batch eliminó 221 166 filas duplicadas o inválidas con `SELECT DISTINCT`.
- El día 17/11 trae 15 456 filas repetidas en el CSV de origen. Como la plantilla de Dataflow no deduplica, las
  elimina el refresco diario (ver "Operación según buenas prácticas").
- Algunas categorías de Olist no tienen pareja en `dim_categoria`, como housewares (5 884 pedidos), cool_stuff
  (3 632) y perfumery (3 162), entre otras.
- 56 669 productos de REES46 no tienen `category_code`.

**Agregar (cola de errores o dead-letter):** el job de Dataflow guarda en `ecommerce.events_deadletter` los
mensajes que rechaza la UDF, con el mensaje original, el error y la fecha, sin detener el flujo. Para probarlo
publicamos tres mensajes defectuosos durante la simulación: un texto que no es JSON, un `event_type` desconocido y
un precio negativo. Los tres llegaron a la tabla de errores en menos de un minuto, cada uno con su causa, y el
resto del streaming siguió entrando a `events_raw`. Como Pub/Sub retiene los mensajes 7 días, los que se corrijan
se pueden volver a publicar.

---

## 7. Ingesta y storage

**Dice (Volumen):** "Unos 25 GB para octubre a diciembre de 2019 ... el dataset completo tiene 285 millones de
eventos según su ficha de Kaggle".

**Debe decir:** "Unos 22 GB sin comprimir (7,06 GiB comprimidos en Cloud Storage) y 177,3 millones de eventos
de octubre a diciembre de 2019, después de eliminar duplicados. Con enero a abril de 2020 son 410,3 millones de
eventos, que ocupan 16,5 GiB comprimidos en Cloud Storage y 55,2 GB lógicos en `events_raw` (~103 GB en todo
BigQuery). Olist suma unos 100 000 pedidos (120 MB)."

**Dice (Velocidad):** "Decenas de eventos por segundo en promedio".

**Debe decir:** "Unos 20 eventos por segundo en un día normal y hasta 140 eventos por segundo en el minuto más
cargado del pico (17/11). La simulación llegó a unos 1 250 eventos por segundo (60x)."

**Dice (REES46, eventos en vivo):** "con un factor de aceleración (por ejemplo 10x)".

**Debe decir:** "con un factor de aceleración de 10x para el día pico (17/11) y de 60x para Black Friday y Cyber
Monday".

---

## Agregar: componentes transversales (retroalimentación del docente)

### 1. Identidades y secretos (IAM y Secret Manager)

En la primera corrida usamos la cuenta de servicio por defecto de Compute Engine, que tenía el rol Editor del
proyecto, y el token de Kaggle se copiaba a la VM. Ahora cada componente tiene su propia cuenta con el mínimo
privilegio (`infra/02_iam.sh`):

| Cuenta de servicio | Componente | Permisos |
|---|---|---|
| `sa-ingesta` | VM de descarga y productor de replay | Escribir en el bucket del proyecto, publicar en el tópico `rees46-events`, leer el secreto `kaggle-token`, leer métricas de Monitoring |
| `sa-dataflow` | Workers de Dataflow | `dataflow.worker`, consumir la suscripción, escribir solo en el dataset `ecommerce`, staging en el bucket |
| `sa-transform` | Consulta programada diaria | Ejecutar consultas (`bigquery.jobUser`) y escribir solo en el dataset `ecommerce` |

El token de Kaggle se guarda en Secret Manager (`kaggle-token`). La VM lo lee al arrancar, así que ya no se copia
desde una laptop ni aparece en el repositorio. Las pruebas están en `docs/evidencia/cuentas_servicio.txt`. Una VM
con `sa-ingesta` leyó el secreto, publicó en el tópico y listó el bucket, pero recibió "acceso denegado" al
intentar consultar BigQuery o crear un tópico. Un job de Dataflow con workers `sa-dataflow` escribió un evento
válido en `events_raw` y dos inválidos en `events_deadletter`. Por último, la consulta programada se ejecutó como
`sa-transform` y reconstruyó sin errores `fact_inventario`, las tablas `agg_*` y los metadatos.

### 2. Gobierno, linaje y calidad (Dataplex Universal Catalog)

- **Capas y metadatos:** cada tabla lleva la etiqueta `capa`, con uno de tres valores. `bronze` corresponde a los
  datos tal como llegan (`events_raw`, `events_deadletter` y `olist_*`), `silver` al modelo integrado (`dim_*` y
  `fact_*`) y `gold` a las tablas de los tableros (`agg_*` y `mv_eventos_hora`). Además, cada tabla tiene la
  etiqueta `fuente` y descripciones de la tabla y de sus columnas clave (`sql/11_governance.sql`). Dataplex las
  cataloga automáticamente y se pueden buscar con `labels.capa=gold`.
- **Glosario de negocio:** creamos `glosario-ecommerce` en Dataplex con 10 términos que definen cómo se calcula
  cada indicador: evento, sesión, pedido, embudo de conversión, tasa de conversión, categoría común, tiempo de
  entrega, quiebre de stock, factor de pico y dato personal (`infra/05_governance.sh`). Las descripciones de las
  columnas hacen referencia al término del glosario que corresponde.
- **Linaje:** con la Data Lineage API activa, cada consulta de BigQuery registra sus tablas de origen y de
  destino. Lo verificamos con la API de linaje. `dim_producto` se construye a partir de `events_raw` y
  `dim_categoria`, `fact_inventario` y `agg_pedidos_hora` a partir de `events_raw`, y `agg_embudo_categoria_dia` a
  partir de `fact_eventos`, que es una vista sobre `events_raw`. El linaje se ve en BigQuery, en la pestaña Linaje
  de cada tabla, y permite seguir un clic desde el dato crudo hasta la métrica de la capa gold.
- **Calidad:** `sql/10_quality.sql` revisa duplicados, categorías sin pareja y eventos por fuente. A eso se suma
  la tabla de errores del streaming (sección 5).

### 3. Cola de errores (dead-letter)

Está descrita en la sección 5. `events_deadletter` aísla los mensajes defectuosos sin detener el flujo, y la
probamos con tres mensajes malformados.

### 4. Control de acceso fino en BigQuery

- **Columnas (policy tags):** creamos la taxonomía `datos-personales` con dos policy tags,
  `identificador_usuario` sobre `events_raw.user_id` e `identificador_cliente` sobre
  `olist_customers.customer_unique_id` (`infra/04_fine_grained_access.py`). Solo el propietario y el equipo, con
  el rol `Fine-Grained Reader`, pueden leer esas columnas. El analista de ejemplo recibe "acceso denegado" si las
  pide, pero puede consultar el resto de la tabla. El enmascaramiento dinámico (SHA-256 para analistas) usa *data
  policies*, que exigen que el proyecto pertenezca a una organización de Google Cloud. Este proyecto se creó con
  una cuenta personal, porque la organización de UTEC no permite crear proyectos, así que el enmascaramiento queda
  como siguiente paso en un entorno con organización.
- **Filas (row access policies):** en `fact_pedidos`, el propietario, el equipo y `sa-transform` ven todas las
  filas, mientras que el analista de ejemplo solo ve la categoría `muebles` (`sql/12_row_access.sql`).

### 5. Operación según buenas prácticas

- **Escritura y deduplicación del streaming.** Dataflow escribe con la Storage Write API
  (`useStorageWriteApi=true`) en lugar de los antiguos *streaming inserts*. Con esto, las filas recién llegadas
  admiten `UPDATE` y `DELETE` de inmediato; lo probamos borrando una fila de prueba segundos después de que
  llegara. Pub/Sub entrega cada mensaje al menos una vez y el CSV de origen trae filas repetidas, así que el
  refresco diario (`sql/14_incremental.sql`) deja una sola copia de cada evento idéntico del streaming dentro de
  una transacción. En total se eliminaron 21 696 filas repetidas: 15 456 del 17/11, 3 606 del 29/11 (4 de ellas
  por reentrega de Pub/Sub) y 2 634 del 02/12. Quedaron 6 379 921, 1 850 824 y 1 738 413 filas, que coinciden con
  el conteo de eventos distintos. Después de la deduplicación pasan los cuatro `ASSERT` de `sql/15_checks.sql`, y
  las dos consultas programadas corren como `sa-transform` sin errores.
- **Refresco incremental.** La consulta programada diaria ya no reconstruye todo con `CREATE OR REPLACE` sobre
  `events_raw`. Ahora lee los metadatos de las particiones, toma solo los días modificados en las últimas 26 h y
  hace `DELETE` e `INSERT` de esos días en `fact_inventario` (por semanas completas) y en los agregados. Cuando no
  hay datos nuevos casi no escanea, y como usa DML, conserva las descripciones, las etiquetas y las row access
  policies. Desde el 6 nov 2026 las dos consultas programadas están en pausa porque los datos ya no cambian.
- **Mínimo privilegio también en la cuenta por defecto.** Le quitamos el rol Editor a la cuenta de servicio por
  defecto de Compute Engine (`infra/02_iam.sh`), que ya no usa ningún componente.
- **Alertas.** Además de la alerta de system lag hay dos más. La primera mide la frescura y avisa si un mensaje
  lleva más de 10 min sin procesarse en la suscripción, lo que indica que el job se cayó o se atascó. La segunda
  avisa si falla cualquier consulta programada, incluida `sql/15_checks.sql`, que corre a las 07:00 con `ASSERT` y
  falla si hay más de 1 000 rechazos en el dead-letter en 24 h, agregados que no cuadran con `events_raw`, claves
  nulas o duplicados del streaming sin limpiar.
- **Infraestructura como código y CI.** `terraform/` describe los recursos persistentes y los adopta con bloques
  `import`. El `terraform plan` da 49 importados, 0 creados y 0 destruidos, y solo vuelve a aplicar etiquetas que
  ya existen. Dejamos fuera, a propósito, las tablas (las crea la capa SQL), el job de Dataflow y la VM (que son
  efímeros), el valor del secreto (no debe quedar en el estado de Terraform), el presupuesto y el glosario.
  `.github/workflows/ci.yml` valida Terraform, shell, Python, JSON y la UDF de Dataflow en cada push. En `main`,
  además, corre `terraform plan` y un dry run del SQL con Workload Identity Federation, sin llaves. El `apply` se
  hace a mano y después de revisarlo.

### 6. Pronóstico de demanda (BigQuery ML)

- **Datos de validación.** Para evaluar el pronóstico con datos que el modelo nunca vio, cargamos enero a abril
  de 2020 desde el mismo espejo: 55,8 M, 54,6 M, 56,2 M y 66,5 M eventos, con 0,83 M, 1,05 M, 1,02 M y 0,97 M
  compras. El dataset público termina en abril de 2020; de mayo en adelante no hay datos en el espejo. La descarga
  corre en una VM efímera que se borra sola a los 30 min (`ingest/fetch_2020.sh`), y la carga se hace con
  `sql/17_load_2020.sql`. En total, `events_raw` queda con 410 M eventos, de octubre de 2019 a abril de 2020.
- **Preparación de la serie.**
  - Taxonomía: los productos que aparecen por primera vez desde diciembre no tienen categoría de oct–nov. Son el
    2,2 % de las compras de diciembre, el 16 % en marzo y el 22 % en abril. `dim_producto` los clasifica con un
    puente: cada `category_id` nuevo toma la categoría de oct–nov de la mayoría de sus productos compartidos,
    siempre que sean al menos 5 y coincida el 80 %. Hay 977 ids con al menos 5 productos compartidos, con un
    acuerdo medio de 94 %, y 862 de ellos superan el 80 %.
  - Días incompletos: el 14 y 15 de noviembre de 2019, el 1 y 2 de enero y el 20 y 21 de abril de 2020, el origen
    dejó de registrar compras aunque la navegación siguió. Estos días se detectan automáticamente, cuando la
    relación entre compras y eventos baja del 60 % de la mediana (vista `v_dias_compras_incompletas`), y se
    excluyen del entrenamiento y de la evaluación.
  - Agregamos dos chequeos a `sql/15_checks.sql`. Uno falla si una categoría se multiplica o se divide por más de
    4 en una semana, lo que habría detectado el salto de diciembre. El otro falla si la proporción de compras sin
    categoría supera el 35 %.
- **Modelo.** Usamos ARIMA_PLUS con una serie diaria de compras por categoría, para las 8 categorías que tienen al
  menos 100 compras al día. Lo entrenamos solo hasta el 31 de diciembre de 2019, con un horizonte de 121 días y un
  intervalo de 90 %. Cada error se compara con una referencia ingenua, que es el promedio diario de oct–dic 2019
  de cada categoría, constante.
- **Resultado (WAPE, todas las categorías).**

  | Tramo | ARIMA_PLUS | Referencia (promedio) |
  |---|---|---|
  | 1–14 ene (dos semanas) | 44,5 % | 11,4 % |
  | ene–feb | 36,1 % | 19,9 % |
  | marzo (confinamiento COVID-19) | 35,3 % | 26,2 % |
  | abril (confinamiento COVID-19) | 39,2 % | 21,3 % |

  En ene–feb, ARIMA gana en muebles, ropa y automotriz, y pierde en electrónica, cómputo, construcción,
  electrodomésticos y niños. El intervalo de 90 % contiene el 93,5 % de los días reales de ene–feb y el 94,2 % de
  ene–abr, aunque solo el 77 % de los primeros 14 días, así que está bien calibrado.
- **Interpretación.** Con tres meses de historia, ARIMA no supera al promedio. El modelo proyecta hacia 2020 el
  nivel alto de diciembre, lo que le da un sesgo positivo, y no puede aprender la estacionalidad anual, como las
  campañas de noviembre o el Año Nuevo. Hace falta al menos un año de historia. Mientras tanto, el promedio es la
  referencia que cualquier modelo tiene que superar, y el intervalo de ARIMA sirve para dimensionar el stock de
  seguridad.
- **Experimento de control con Olist (`sql/18_forecast_olist.sql`).** Para saber si el problema era la falta de
  historia o el modelo, repetimos la prueba con Olist, que tiene 17 meses antes del corte (de enero de 2017 a mayo
  de 2018, incluido un Black Friday). Las series son los pedidos diarios de las 6 categorías con al menos 15
  pedidos al día, más el total. El periodo de prueba va del 1 de junio al 22 de agosto de 2018, porque los días
  siguientes están incompletos en el dataset público. Comparamos cinco métodos:
  - ARIMA_PLUS con 17 meses y con 3 meses (la misma historia que en REES46), con los feriados de Brasil.
  - XGBoost (`BOOSTED_TREE_REGRESSOR`) entrenado directamente para horizontes de 1 a 83 días. Usa orígenes
    semanales desde abril de 2017 y como objetivo los pedidos divididos entre el promedio de los 28 días previos al
    origen. Las variables son la serie, el horizonte, el día de semana, el día del mes, los feriados y el perfil
    del día de semana de las 8 semanas previas. No extrapola tendencias.
  - TimesFM (`AI.FORECAST`), el modelo preentrenado de Google, que no requiere entrenamiento propio, con los 17
    meses.
  - El promedio diario de mar–may 2018 de cada serie, constante.

  | Tramo (WAPE, categorías) | ARIMA 17 m | ARIMA 3 m | XGBoost | TimesFM | Promedio 3 m |
  |---|---|---|---|---|---|
  | 1–14 jun | 42,7 % | 32,5 % | 29,0 % | 40,9 % | 27,2 % |
  | jun–jul | 43,4 % | 35,6 % | 31,9 % | 42,2 % | 30,9 % |
  | 1–22 ago | 51,7 % | 44,7 % | 24,4 % | 51,2 % | 27,6 % |

  - Con más historia, ARIMA empeora. Con 17 meses pronostica 111 pedidos por día en la serie total, cuando los
    reales son 203; con 3 meses pronostica 206. TimesFM tiene el mismo problema (100). Los dos le dan mucho peso a
    la última semana antes del corte, que fue anormalmente baja: del 24 al 31 de mayo de 2018 hubo entre 99 y 144
    pedidos por día, lo que coincide con el paro de camioneros en Brasil. Además, ARIMA arrastra el crecimiento de
    2017.
  - XGBoost es el único método que se acerca al promedio. Es 1,8 puntos peor en 1–14 jun y 1,0 punto peor en
    jun–jul, y lo supera en agosto (24,4 % contra 27,6 %). En la serie total, el mejor es ARIMA con 3 meses (19,1 %
    contra 22,7 % del promedio).
  - Interpretación: el problema no está solo en el modelo. Sin dos años de datos, ningún método aprende la
    estacionalidad anual, y si el corte cae en una anomalía, los modelos que siguen el nivel reciente salen
    castigados. Un modelo de árboles con variables relativas al nivel es la alternativa más robusta, aunque no
    supera a la referencia con claridad.
  - Costo: el ARIMA de REES46 factura 21 MB por entrenamiento. Los jobs de ARIMA y TimesFM de Olist no reportan
    bytes en `INFORMATION_SCHEMA.JOBS`, así que su costo no está medido. XGBoost se entrena fuera del motor de
    consultas y facturó 50,8 GB (50 755 272 704 bytes) con la tarifa de BigQuery ML, en unos 18 min. Como no admite
    `--dry_run`, el script no debería volver a entrenarlo si no hace falta.
- **Costo.** Entrenar y evaluar solo lee la tabla gold `agg_embudo_categoria_dia`, que pesa unos KB. Con seis
  meses de datos, reconstruir silver y gold desde cero factura unos 67 GB (unos 0,41 USD a precio de lista). Por
  eso subimos el tope por script de `sql/run.sh` (`MAX_BYTES_BILLED`) de 50 GB a 100 GB.
