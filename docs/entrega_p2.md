# Entrega P2: procesamiento, transformación y modelado

**Grupo 1 · Big Data · UTEC Posgrado.** Proyecto GCP `bigdata-g1-ecommerce-1105`. En este documento indicamos,
para cada criterio de la rúbrica, dónde está el código en el repositorio y dónde está la evidencia de su
ejecución. Todo lo que se describe aquí está desplegado y se ejecutó sobre los datos reales: REES46, con 410 M
eventos de octubre de 2019 a abril de 2020, y Olist, con 99 470 pedidos de 2016 a 2018.

| Criterio | Dónde está | Evidencia |
|---|---|---|
| Pipelines de cómputo y transformación: limpieza, enriquecimiento y cruce de datos heterogéneos | SQL en BigQuery (`sql/02` a `sql/06`, `sql/14`, `sql/17`) y Apache Beam en Dataflow (`streaming/beam/pipeline.py`) | `docs/correcciones_documento.md` (secciones 5 y 6), `docs/evidencia/sql_post_replay.txt` |
| Procesamiento híbrido: tiempo real y lotes | Tiempo real: Pub/Sub → Dataflow (plantilla con UDF y pipeline Beam propio). Lotes: `bq load` + SQL y una consulta programada incremental diaria | `docs/evidencia/replays.log`, `docs/evidencia/metricas_pico.csv`, `docs/evidencia/beam_conciliacion.txt` |
| Modelado para analítica: estructuras finales listas para su consumo | Capas bronze, silver y gold; esquema en constelación con dimensiones compartidas (`sql/03`, `sql/04`, `sql/05`, `sql/19`) | Looker Studio (7 páginas) lee solo tablas gold; `sql/09_bytes_scanned.sh` |

## 1. Pipelines de transformación

### Limpieza

| Paso | Código | Resultado medido |
|---|---|---|
| Tipado y descarte de filas inválidas en la carga batch (todo llega como STRING a `events_staging`) | `sql/02_load_events.sql`, `sql/17_load_2020.sql` | 221 166 filas duplicadas o inválidas eliminadas en oct–dic 2019 |
| Validación de cada mensaje en tiempo real: formato de fecha, tipo de evento, `product_id` entero, precio no negativo | `streaming/udf/transform.js` (plantilla) y `parse_event` en `streaming/beam/pipeline.py` | Los inválidos van a `events_deadletter` con su motivo, sin detener el flujo: 3 de 3 mensajes de prueba en cada job |
| Deduplicación del streaming (Pub/Sub entrega al menos una vez) | `sql/14_incremental.sql` (consulta programada 06:00) | 21 696 filas repetidas eliminadas |
| Días con el registro de compras caído en el origen | Vista `v_dias_compras_incompletas` en `sql/16_forecast.sql` | Detecta sola 14–15 nov 2019, 1–2 ene y 20–21 abr 2020 |
| Chequeos diarios con ASSERT | `sql/15_checks.sql` (07:00) | Claves nulas, duplicados, agregados que no cuadran con la capa raw, saltos de más de 4x |

### Enriquecimiento

- **Categoría estable por producto** (`sql/03_dims.sql`). Desde diciembre de 2019 el origen cambió la numeración
  de `category_id`, y el 76 % de las compras de diciembre traía una categoría distinta a la que tenía el producto
  en oct–nov. Por eso `dim_producto` fija una sola categoría por producto. Los productos nuevos la heredan a
  través de un puente: cada `category_id` nuevo toma la categoría de la mayoría de sus productos compartidos,
  siempre que sean al menos 5 y haya un 80 % de acuerdo. El acuerdo medio que medimos es de 94 %.
- **Categoría común entre fuentes** (`seed/dim_categoria.csv`, que se carga en `dim_categoria`). Asigna las
  categorías de REES46 y de Olist a 18 categorías comunes, de las cuales 13 aparecen en REES46. Esta es la clave
  que permite cruzar las dos tiendas.
- **En tiempo real** (`streaming/beam/pipeline.py`). Dentro del stream, cada evento recibe la categoría común de
  su producto. Para eso el pipeline usa como side input una exportación de `dim_producto` con 386 299 productos.
- **Tiempo y logística** (`sql/04_facts.sql`). Olist registra la hora de São Paulo, que convertimos a UTC.
  También calculamos los días hasta el despacho, los días de entrega y el atraso respecto a la fecha estimada, y
  tomamos el medio de pago principal de cada pedido.
- **Inventario derivado** (`sql/06_fact_inventory.sql`). REES46 no incluye stock, así que partimos de un supuesto
  explícito: cada producto empieza la semana con 50 unidades, cada compra descuenta una y el lunes se repone. A
  partir de eso calculamos los quiebres de stock y la demanda no atendida.

### Cruce de fuentes heterogéneas

Las fuentes son de distinto tipo: eventos de clic en CSV y en mensajes JSON (REES46), pedidos relacionales en 9
tablas (Olist) y un inventario derivado. Los cruces se hacen en `sql/05_analytics.sql`:

| Cruce | Tabla gold | Une por |
|---|---|---|
| Demanda vs. inventario derivado | `agg_demanda_vs_inventario` | Producto y día |
| Conversión de REES46 vs. cumplimiento de Olist | `agg_conversion_vs_cumplimiento` | Categoría común |
| Patrón hora × día de semana de ambas tiendas | `agg_patron_horario` | Hora y día de semana |

Hay que tener en cuenta que Olist (Brasil, 2016–2018) y REES46 (2019–2020) no corresponden a la misma tienda ni
al mismo periodo. Por eso el cruce se hace por categoría y por patrón horario, lo que sirve para demostrar la
integración, pero no para sacar conclusiones de negocio.

## 2. Procesamiento híbrido

| | Tiempo real | Lotes |
|---|---|---|
| Entrada | Pub/Sub `rees46-events`, con una suscripción por consumidor | Cloud Storage (CSV y CSV.gz) |
| Motor | Dataflow: plantilla Pub/Sub → BigQuery con UDF, y pipeline Apache Beam propio | BigQuery SQL: `bq load` y consultas programadas |
| Transformaciones | Validación y cola de errores (ambos jobs); enriquecimiento y agregación por minuto (Beam) | Tipado, deduplicación, dimensiones, hechos, agregados, inventario |
| Destino | `events_raw` (bronze) y `stream_categoria_minuto` (gold) | silver y gold |
| Frecuencia y latencia | Continua. Plantilla: retraso máximo de 7 s a 60x. Beam: cada minuto queda escrito 3–4 min después de cerrar su ventana, con 1 worker a 10x (p50 189 s) | Carga inicial única; refresco incremental diario a las 06:00 que solo procesa las particiones modificadas en 26 h |

**Pipeline Beam** (`streaming/beam/pipeline.py`):

```
Pub/Sub (rees46-events-beam)
  → Validar          (inválidos → events_deadletter)
  → Enriquecer       (side input: producto → categoría común, desde dim_producto)
  → VentanaMinuto    (ventanas fijas de 1 min por hora de llegada; tardíos aceptados 10 min)
  → PorMinutoYCategoria → Contar (vistas, carritos, remociones, compras, ingresos)
  → stream_categoria_minuto (BigQuery, gold)
```

**Prueba de punta a punta.** `streaming/beam/test_replay.sh` reproduce desde una VM, a 10x, el tramo de 10:30 a
11:00 del 17/11/2019, que es el día pico real. Luego `ecommerce.conciliar_stream` compara el resultado con el mismo
agregado calculado por lotes sobre `fact_eventos`:

| Indicador | Stream | Batch |
|---|---|---|
| Combinaciones minuto × categoría | 379 | 379 (todas coinciden) |
| Eventos | 227 830 | 227 830 |
| Compras | 7 134 | 7 134 |
| Ingresos | 2 324 635,61 | 2 324 635,61 |

El test unitario (`streaming/beam/test_pipeline.py`, con DirectRunner) prueba la validación, el enriquecimiento,
el caso de un producto desconocido y la cola de errores. Se ejecuta en cada push en GitHub Actions.

**Replays del pico con la plantilla.** Reprodujimos el 17/11 a 10x, y Black Friday y Cyber Monday a 60x (unos
1 250 eventos por segundo). Se enviaron 9 990 850 mensajes sin fallos de publicación y todos llegaron a
`events_raw`. Durante la prueba, Dataflow pasó de 1 a 2 workers.

## 3. Modelado para analítica

### Capas

| Capa | Tablas | Rol |
|---|---|---|
| bronze | `events_raw` (410 M filas, particionada por día y con clustering por `event_type` y `category_code`), `events_deadletter`, `olist_*` | Datos tal como llegan, tipados |
| silver | `dim_fecha`, `dim_categoria`, `dim_producto`, `fact_eventos`, `fact_pedidos`, `fact_inventario` | Modelo integrado |
| gold | `agg_*` (8 tablas de KB), `mv_eventos_hora`, `stream_categoria_minuto`, `ml_*` | Listas para su consumo en Looker Studio y en el pronóstico |

Cada tabla lleva las etiquetas `capa` y `fuente`, además de descripciones por columna (`sql/11_governance.sql`).
Dataplex las cataloga junto con el glosario y el linaje.

### Esquema

Usamos un esquema en constelación, con tres tablas de hechos que comparten las dimensiones de fecha y de
categoría común. La categoría queda en copo de nieve, porque el evento se relaciona con ella a través del
producto.

```mermaid
erDiagram
  dim_fecha ||--o{ fact_eventos : "fecha"
  dim_fecha ||--o{ fact_pedidos : "fecha_compra"
  dim_fecha ||--o{ fact_inventario : "fecha"
  dim_producto ||--o{ fact_eventos : "product_id"
  dim_producto ||--o{ fact_inventario : "product_id"
  dim_categoria }o--|| categoria_comun : "mapea fuente a"
  dim_producto }o--|| categoria_comun : "categoria_comun"
  fact_pedidos }o--|| categoria_comun : "categoria_comun"

  dim_fecha {
    DATE fecha PK
    INT anio
    INT mes
    STRING dia_semana
    BOOL fin_de_semana
    STRING evento "Black Friday o Cyber Monday"
  }
  dim_producto {
    INT product_id PK
    STRING categoria_comun FK
    STRING categoria_rees46
    STRING brand
    NUMERIC precio_mediano
    STRING origen_categoria "oct-nov, puente o nulo"
  }
  dim_categoria {
    STRING fuente "rees46 u olist"
    STRING categoria_fuente
    STRING categoria_comun FK
  }
  categoria_comun {
    STRING categoria_comun PK "18 valores"
  }
  fact_eventos {
    TIMESTAMP event_time
    STRING event_type
    INT product_id FK
    NUMERIC price
    INT user_id
    STRING user_session
  }
  fact_pedidos {
    STRING order_id
    DATE fecha_compra FK
    STRING categoria_comun FK
    INT items
    FLOAT valor_items
    FLOAT valor_flete
    FLOAT dias_entrega
    INT dias_vs_estimado
  }
  fact_inventario {
    INT product_id FK
    DATE fecha FK
    INT unidades_vendidas
    INT stock_fin_dia
    BOOL quiebre
    INT demanda_no_atendida
  }
```

| Tabla | Grano | Filas | Partición / clustering |
|---|---|---|---|
| `fact_eventos` | Un evento (vista sobre `events_raw`, sin copia) | 410 M | Hereda la partición diaria de `events_raw` |
| `fact_pedidos` | Pedido × categoría (Olist) | 99 470 | Mes de compra / `categoria_comun` |
| `fact_inventario` | Producto × día | 1,53 M | Día / `product_id` |
| `dim_producto` | Producto | 386 299 | — / `product_id` |
| `dim_fecha` | Día (sep 2016 – abr 2020) | 1 338 | — |
| `dim_categoria` | Categoría de origen → categoría común | 85 | — |
| `stream_categoria_minuto` | Minuto del evento × categoría, por ventana de llegada | En tiempo real | Día / `categoria_comun` |

### Listo para su consumo

- **Tableros.** Looker Studio (7 páginas) solo lee tablas gold de pocos KB. Responde entre 0,17 y 0,25 s sin
  caché, y ninguna consulta del tablero toca `events_raw`.
- **Costo de consulta.** Sobre `events_raw`, la misma pregunta escanea 52 668 MB con `SELECT *` y 9,6 MB si se
  filtra un día de la partición. Sobre la tabla agregada escanea 0,2 MB (`sql/09_bytes_scanned.sh`).
- **Pronóstico.** BigQuery ML (`sql/16` y `sql/18`) se entrena directamente sobre la tabla gold
  `agg_embudo_categoria_dia`.

## Cómo reproducir

El orden completo de ejecución está en la sección Ejecución del `README.md`. Para lo que corresponde a esta
entrega:

```bash
./ingest/bq_load.sh                                 # lotes: carga, limpieza, dims, hechos y agregados
sql/run.sh sql/19_stream_aggregates.sql             # tabla gold del stream + conciliar_stream
./streaming/beam/launch.sh                          # pipeline Beam en Dataflow
./streaming/beam/test_replay.sh "2019-11-17 10:30:00" "2019-11-17 11:00:00"
bq query --use_legacy_sql=false \
  "SELECT * FROM ecommerce.conciliar_stream('2019-11-17 10:30:00', '2019-11-17 11:00:00') WHERE NOT coincide"
./streaming/stop_dataflow.sh
```

## Limitaciones conocidas

- **Latencia del pipeline Beam.** Cada minuto queda escrito 3 a 4 min después de cerrar su ventana. Lo medimos a
  10x con 1 worker `n1-standard-2`, y no lo probamos con más workers ni al ritmo real (~20 eventos por segundo).
- **Ventanas por hora de llegada.** Las ventanas usan la hora de publicación en Pub/Sub, y la clave incluye el
  minuto del evento. Con eventos en vivo, las dos horas coinciden. Si las ventanas se armaran por hora del evento,
  un replay de datos de 2019 quedaría años por detrás del watermark de Dataflow y se descartaría como tardío.
- **Inventario derivado.** Sale de un supuesto (50 unidades por producto y semana) y no de datos reales.
- **REES46 y Olist** no comparten tienda ni periodo (ver Cruce de fuentes heterogéneas).
