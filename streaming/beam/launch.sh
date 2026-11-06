#!/usr/bin/env bash
# Launches the Beam streaming job (streaming/beam/pipeline.py) on Dataflow, next to the template job.
# Needs a Python 3.12 environment with apache-beam[gcp] (Dataflow does not run 3.14):
#   uv venv -p 3.12 ~/.venvs/beam312 && uv pip install -p ~/.venvs/beam312/bin/python "apache-beam[gcp]==2.66.0"
# Usage: streaming/beam/launch.sh [python]   (default ~/.venvs/beam312/bin/python)
#        UPDATE_JOB=<job name> streaming/beam/launch.sh   replaces the running job keeping its state (--update)
# Behind a TLS-inspecting proxy whose CA is in the system store, point the Python clients at it:
#   export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt HTTPLIB2_CA_CERTS=$REQUESTS_CA_BUNDLE
# Stop it with streaming/stop_dataflow.sh (drains every active job, this one included).
set -euo pipefail
cd "$(dirname "$0")/../.."
source config.env
PY="${1:-$HOME/.venvs/beam312/bin/python}"
LOOKUP="gs://$BUCKET/lookup/dim_producto_categoria"

# Product -> category lookup for the side input, exported from dim_producto (the workers only read GCS)
bq query --project_id="$PROJECT_ID" --location="$BQ_LOCATION" --use_legacy_sql=false \
  --maximum_bytes_billed="$MAX_BYTES_BILLED" --label=componente:dataflow >/dev/null <<SQL
EXPORT DATA OPTIONS (uri = '$LOOKUP-*.csv', format = 'CSV', header = TRUE, overwrite = TRUE) AS
SELECT product_id, IFNULL(categoria_comun, 'sin_categoria') AS categoria_comun FROM $DATASET.dim_producto
SQL

"$PY" streaming/beam/pipeline.py \
  --subscription="projects/$PROJECT_ID/subscriptions/$SUBSCRIPTION_BEAM" \
  --lookup="$LOOKUP-*.csv" \
  --output_table="$PROJECT_ID:$DATASET.stream_categoria_minuto" \
  --deadletter_table="$PROJECT_ID:$DATASET.events_deadletter" \
  --runner=DataflowRunner --project="$PROJECT_ID" --region="$REGION" \
  --job_name="${UPDATE_JOB:-rees46-beam-$(date +%Y%m%d-%H%M%S)}" ${UPDATE_JOB:+--update} \
  --service_account_email="$SA_DATAFLOW" \
  --temp_location="gs://$BUCKET/dataflow/temp" --staging_location="gs://$BUCKET/dataflow/staging" \
  --enable_streaming_engine --num_workers=1 --max_num_workers="$DF_MAX_WORKERS" \
  --machine_type="$DF_MACHINE" --labels=componente=dataflow --save_main_session
