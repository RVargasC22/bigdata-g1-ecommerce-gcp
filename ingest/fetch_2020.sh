#!/usr/bin/env bash
# Extends REES46 with Jan-Mar 2020 (real holdout for the demand forecast, sql/16_forecast.sql).
# Small self-deleting VM (sa-ingesta, 30 min max) runs ingest/download_2020.sh as startup script.
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

gcloud compute instances create ingest-2020 --project="$PROJECT_ID" --zone="$ZONE" \
  --machine-type=e2-standard-2 --boot-disk-size=10GB --image-family=debian-12 --image-project=debian-cloud \
  --service-account="$SA_INGESTA" --scopes=cloud-platform --labels=componente=ingesta \
  --max-run-duration=30m --instance-termination-action=DELETE \
  --metadata=bucket="$BUCKET" --metadata-from-file=startup-script=ingest/download_2020.sh
echo "Waiting for gs://$BUCKET/raw/rees46/_2020_listo.txt ..."
