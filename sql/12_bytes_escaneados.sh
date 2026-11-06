#!/usr/bin/env bash
# Evidence for partitioning + clustering + column selection: bytes a query would scan (dry run, free).
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

dry() {
  local label="$1" q="$2"
  local bytes
  bytes=$(bq query --project_id="$PROJECT_ID" --location="$BQ_LOCATION" --use_legacy_sql=false \
            --dry_run --format=json "$q" | python3 -c "import json,sys; print(json.load(sys.stdin)['statistics']['totalBytesProcessed'])")
  printf "%-45s %12.1f MB\n" "$label" "$(echo "$bytes / 1048576" | bc -l)"
}

dry "SELECT * , sin filtro"                      "SELECT * FROM ecommerce.events_raw"
dry "3 columnas, sin filtros"                    "SELECT event_type, price, category_code FROM ecommerce.events_raw"
dry "3 columnas, solo purchase (clustering)"     "SELECT event_type, price, category_code FROM ecommerce.events_raw WHERE event_type='purchase'"
dry "3 columnas, 2019-11-17 (particion)"       "SELECT event_type, price, category_code FROM ecommerce.events_raw WHERE DATE(event_time)='2019-11-17' AND event_type='purchase'"
dry "Tablero: agg_pedidos_hora"                  "SELECT hora, pedidos, ingresos FROM ecommerce.agg_pedidos_hora"
