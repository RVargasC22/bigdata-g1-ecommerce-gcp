#!/usr/bin/env bash
# Snapshots of critical tables into ecommerce_dr (30-day expiry). Snapshots only bill changed bytes.
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env
TAG=$(date +%Y%m%d_%H%M)
for t in events_raw fact_pedidos fact_inventario dim_categoria; do
  bq --project_id="$PROJECT_ID" cp --snapshot --no_clobber --expiration=2592000 \
    "$DATASET.$t" "$DR_DATASET.${t}_$TAG"
done
bq ls --project_id="$PROJECT_ID" "$DR_DATASET"
