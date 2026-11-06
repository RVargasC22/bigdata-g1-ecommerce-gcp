#!/usr/bin/env bash
# Drains active streaming jobs: finishes in-flight messages, nothing lost, then stops billing.
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env
for r in "$REGION" "$DR_REGION"; do
  for id in $(gcloud dataflow jobs list --region="$r" --status=active --format="value(id)"); do
    echo "Draining $id ($r)"; gcloud dataflow jobs drain "$id" --region="$r"
  done
done
