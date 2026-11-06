#!/usr/bin/env bash
# Batch path: gs://BUCKET/raw -> BigQuery (bq load is free, unlike streaming inserts).
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env
BQ="bq --project_id=$PROJECT_ID --location=$BQ_LOCATION"

sql/run.sh sql/01_ddl.sql

echo "== REES46 -> events_staging"
$BQ load --replace --source_format=CSV --skip_leading_rows=1 \
  ecommerce.events_staging "gs://$BUCKET/raw/rees46/*.csv.gz" \
  event_time:STRING,event_type:STRING,product_id:STRING,category_id:STRING,category_code:STRING,brand:STRING,price:STRING,user_id:STRING,user_session:STRING
sql/run.sh sql/02_load_events.sql

echo "== Olist -> olist_*"
for t in customers geolocation order_items order_payments order_reviews orders products sellers; do
  $BQ load --replace --autodetect --source_format=CSV --skip_leading_rows=1 --allow_quoted_newlines \
    "ecommerce.olist_$t" "gs://$BUCKET/raw/olist/olist_${t}_dataset.csv"
done
# Explicit schema: header of this file starts with a BOM
$BQ load --replace --source_format=CSV --skip_leading_rows=1 \
  ecommerce.olist_category_translation "gs://$BUCKET/raw/olist/product_category_name_translation.csv" \
  product_category_name:STRING,product_category_name_english:STRING

echo "== Manual category map -> dim_categoria"
$BQ load --replace --source_format=CSV --skip_leading_rows=1 \
  ecommerce.dim_categoria seed/dim_categoria.csv \
  categoria_comun:STRING,fuente:STRING,categoria_fuente:STRING

sql/run.sh sql/03_dims.sql sql/04_facts.sql sql/12_row_access.sql sql/06_fact_inventory.sql \
  sql/05_analytics.sql sql/11_governance.sql sql/10_quality.sql
