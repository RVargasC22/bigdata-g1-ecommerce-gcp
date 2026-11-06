#!/usr/bin/env bash
# Extends REES46 with 2020 months (real holdout for the demand forecast, sql/16_forecast.sql).
# The public dataset ends in April 2020. Usage: ingest/fetch_2020.sh [months]   (default: 2020-Jan .. 2020-Apr)
# 1. Small self-deleting VM (sa-ingesta, 30 min max) runs ingest/download_2020.sh: mirror -> GCS.
# 2. bq load of those files into ecommerce.events_staging_2020. Next step: sql/run.sh sql/17_load_2020.sql
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env
MONTHS="${*:-2020-Jan 2020-Feb 2020-Mar 2020-Apr}"
MARKER="gs://$BUCKET/raw/rees46/_2020_done.txt"

gcloud storage rm "$MARKER" 2>/dev/null || true
gcloud compute instances create ingest-2020 --project="$PROJECT_ID" --zone="$ZONE" \
  --machine-type=e2-standard-2 --boot-disk-size=10GB --image-family=debian-12 --image-project=debian-cloud \
  --service-account="$SA_INGESTA" --scopes=cloud-platform --labels=componente=ingesta \
  --max-run-duration=30m --instance-termination-action=DELETE \
  --metadata=bucket="$BUCKET",months="$MONTHS" --metadata-from-file=startup-script=ingest/download_2020.sh

echo "Waiting for $MARKER ..."
for _ in $(seq 60); do
  gcloud storage ls "$MARKER" >/dev/null 2>&1 && break
  sleep 30
done
gcloud storage ls "$MARKER" >/dev/null

URIS=$(for m in $MONTHS; do printf 'gs://%s/raw/rees46/%s.csv.gz,' "$BUCKET" "$m"; done)
bq --project_id="$PROJECT_ID" --location="$BQ_LOCATION" load --replace --source_format=CSV --skip_leading_rows=1 \
  ecommerce.events_staging_2020 "${URIS%,}" \
  event_time:STRING,event_type:STRING,product_id:STRING,category_id:STRING,category_code:STRING,brand:STRING,price:STRING,user_id:STRING,user_session:STRING
echo "Staged $MONTHS. Next: sql/run.sh sql/17_load_2020.sql"
