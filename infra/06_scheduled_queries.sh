#!/usr/bin/env bash
# Scheduled queries, both run as sa-transform. Creates or updates.
#   06:00 UTC  sql/14_incremental.sql   stream dedup + incremental refresh of fact_inventario and aggregates
#   07:00 UTC  sql/15_checks.sql        data-quality ASSERTs (failure -> monitoring/alert_scheduled_query.json)
# DML keeps descriptions, labels and row access policies, so 11_governance / 12_row_access are not rerun.
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

OLD_NAME="refresco-diario-inventario-agregados"   # previous full rebuild (05 + 06 + 11), renamed below

configs() {
  bq ls --transfer_config --transfer_location="$BQ_LOCATION" --project_id="$PROJECT_ID" --format=json
}
find_config() {
  configs | python3 -c 'import json,sys; print(next((c["name"] for c in json.load(sys.stdin) if c["displayName"] in sys.argv[1:]), ""))' "$@"
}
schedule() {  # name schedule sql_file [old_name]
  local PARAMS CONFIG
  PARAMS=$(python3 -c 'import json,sys; print(json.dumps({"query": open(sys.argv[1]).read()}))' "$3")
  CONFIG=$(find_config "$1" "${4:-$1}")
  if [ -n "$CONFIG" ]; then
    bq update --transfer_config --update_credentials --service_account_name="$SA_TRANSFORM" \
      --display_name="$1" --schedule="$2" --params="$PARAMS" "$CONFIG"
  else
    bq mk --transfer_config --project_id="$PROJECT_ID" --location="$BQ_LOCATION" \
      --data_source=scheduled_query --display_name="$1" --schedule="$2" \
      --service_account_name="$SA_TRANSFORM" --params="$PARAMS"
  fi
}

schedule "refresco-diario-incremental" "every day 06:00" sql/14_incremental.sql "$OLD_NAME"
schedule "chequeos-calidad-diarios" "every day 07:00" sql/15_checks.sql
