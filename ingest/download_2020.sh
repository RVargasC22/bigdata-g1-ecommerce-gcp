#!/bin/bash
# VM startup script: streams the REES46 Jan-Mar 2020 files from the author's mirror straight into
# gs://BUCKET/raw/rees46/ (no local disk), then writes a marker. The VM deletes itself (--max-run-duration).
# Launched by: ingest/fetch_2020.sh
set -euo pipefail
BUCKET=$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/bucket)
for m in 2020-Jan 2020-Feb 2020-Mar; do
  curl -sSf "https://data.rees46.com/datasets/marketplace/$m.csv.gz" | gcloud storage cp - "gs://$BUCKET/raw/rees46/$m.csv.gz"
done
echo "ok $(date -u +%FT%TZ)" | gcloud storage cp - "gs://$BUCKET/raw/rees46/_2020_listo.txt"
