#!/bin/bash
# VM startup script: streams REES46 2020 monthly files from the author's mirror straight into
# gs://BUCKET/raw/rees46/ (no local disk), then writes a marker. The VM deletes itself (--max-run-duration).
# Launched by: ingest/fetch_2020.sh (instance metadata: bucket, months)
set -euo pipefail
md() { curl -s -H 'Metadata-Flavor: Google' "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1"; }
BUCKET=$(md bucket)
for m in $(md months); do
  curl -sSf "https://data.rees46.com/datasets/marketplace/$m.csv.gz" | gcloud storage cp - "gs://$BUCKET/raw/rees46/$m.csv.gz"
done
echo "ok $(date -u +%FT%TZ)" | gcloud storage cp - "gs://$BUCKET/raw/rees46/_2020_done.txt"
