#!/usr/bin/env bash
# Starts the streaming job (Google template Pub/Sub -> BigQuery + JS UDF + dead-letter table).
# Usage: streaming/launch_dataflow.sh [region]   (pass DR_REGION for failover)
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env
RUN_REGION="${1:-$REGION}"

gcloud storage cp streaming/udf/transform.js "gs://$BUCKET/udf/transform.js"
gcloud dataflow flex-template run "rees46-stream-$(date +%Y%m%d-%H%M%S)" \
  --project="$PROJECT_ID" --region="$RUN_REGION" \
  --template-file-gcs-location="gs://dataflow-templates-$RUN_REGION/latest/flex/PubSub_to_BigQuery_Flex" \
  --parameters="inputSubscription=projects/$PROJECT_ID/subscriptions/$SUBSCRIPTION" \
  --parameters="outputTableSpec=$PROJECT_ID:$DATASET.events_raw" \
  --parameters="outputDeadletterTable=$PROJECT_ID:$DATASET.events_deadletter" \
  --parameters="javascriptTextTransformGcsPath=gs://$BUCKET/udf/transform.js" \
  --parameters="javascriptTextTransformFunctionName=transform" \
  --parameters="useStorageWriteApi=true,numStorageWriteApiStreams=3,storageWriteApiTriggeringFrequencySec=5" \
  --num-workers=1 --max-workers="$DF_MAX_WORKERS" --worker-machine-type="$DF_MACHINE" \
  --enable-streaming-engine --service-account-email="$SA_DATAFLOW" \
  --staging-location="gs://$BUCKET/dataflow/staging" --temp-location="gs://$BUCKET/dataflow/temp" \
  --additional-user-labels=componente=dataflow
