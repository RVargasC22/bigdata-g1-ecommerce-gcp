-- Curated event table: target of both the batch load and the Dataflow stream.
CREATE TABLE IF NOT EXISTS ecommerce.events_raw (
  event_time    TIMESTAMP NOT NULL,
  event_type    STRING NOT NULL,
  product_id    INT64,
  category_id   INT64,
  category_code STRING,
  brand         STRING,
  price         NUMERIC,
  user_id       INT64,
  user_session  STRING,
  source        STRING,      -- 'batch' | 'stream'
  ingest_time   TIMESTAMP
)
PARTITION BY DATE(event_time)
CLUSTER BY event_type, category_code
OPTIONS (labels = [('componente', 'bigquery')]);

-- Landing table for bq load: everything as STRING, parsed and deduplicated into events_raw.
CREATE TABLE IF NOT EXISTS ecommerce.events_staging (
  event_time STRING, event_type STRING, product_id STRING, category_id STRING,
  category_code STRING, brand STRING, price STRING, user_id STRING, user_session STRING
)
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY),
         labels = [('componente', 'bigquery')]);
