#!/usr/bin/env bash
# Stops everything that bills by the hour. Data (bucket, BigQuery) is kept.
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env
streaming/stop_dataflow.sh
gcloud compute instances delete "$VM_NAME" --zone="$ZONE" --quiet 2>/dev/null || echo "VM already gone"
echo "Hourly resources stopped. To delete ALL data too: gcloud projects delete $PROJECT_ID"
