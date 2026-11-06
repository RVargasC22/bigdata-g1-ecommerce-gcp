#!/usr/bin/env bash
# Stops everything that bills by the hour. Data (bucket, BigQuery) is kept.
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env
streaming/stop_dataflow.sh
for vm in "$VM_NAME" replay-beam; do   # replay-beam: streaming/beam/test_replay.sh
  gcloud compute instances delete "$vm" --zone="$ZONE" --quiet 2>/dev/null || echo "VM $vm already gone"
done
echo "Hourly resources stopped. To delete ALL data too: gcloud projects delete $PROJECT_ID"
