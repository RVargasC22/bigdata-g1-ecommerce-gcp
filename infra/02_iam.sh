#!/usr/bin/env bash
# Dedicated service accounts with least privilege (one per component) + Kaggle token in Secret Manager.
# Replaces the default Compute Engine service account (project Editor) used in the first run. Idempotent.
#   sa-ingesta   VM: Kaggle -> GCS, replay producer -> Pub/Sub, reads Monitoring metrics
#   sa-dataflow  Dataflow workers: Pub/Sub subscription -> BigQuery (events_raw / events_deadletter)
#   sa-transform Scheduled query: rebuilds fact_inventario and agg_* tables
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

gcloud services enable secretmanager.googleapis.com iam.googleapis.com --project="$PROJECT_ID"

create_sa() {
  gcloud iam service-accounts describe "$1@$PROJECT_ID.iam.gserviceaccount.com" --project="$PROJECT_ID" >/dev/null 2>&1 || \
    gcloud iam service-accounts create "$1" --project="$PROJECT_ID" --display-name="$2"
}
create_sa sa-ingesta   "Ingesta: VM de descarga y productor de replay"
create_sa sa-dataflow  "Dataflow: Pub/Sub -> BigQuery"
create_sa sa-transform "Consultas programadas de BigQuery"

project_role() {
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$1" --role="$2" \
    --condition=None --quiet >/dev/null
}
dataset_role() {  # SQL DCL: `bq add-iam-policy-binding` on datasets needs allowlisting
  bq query --project_id="$PROJECT_ID" --location="$BQ_LOCATION" --use_legacy_sql=false \
    "GRANT \`$2\` ON SCHEMA \`$PROJECT_ID\`.$DATASET TO 'serviceAccount:$1'" >/dev/null
}

# Kaggle token: stored once in Secret Manager, never copied with scp or written in the repo
if ! gcloud secrets describe kaggle-token --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud secrets create kaggle-token --project="$PROJECT_ID" --replication-policy=automatic \
    --data-file="$HOME/.kaggle/access_token" --labels=componente=ingesta
fi

# sa-ingesta: only its bucket, only publish to its topic, only its secret
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member="serviceAccount:$SA_INGESTA" --role=roles/storage.objectUser >/dev/null
gcloud pubsub topics add-iam-policy-binding "$TOPIC" --project="$PROJECT_ID" \
  --member="serviceAccount:$SA_INGESTA" --role=roles/pubsub.publisher >/dev/null
gcloud secrets add-iam-policy-binding kaggle-token --project="$PROJECT_ID" \
  --member="serviceAccount:$SA_INGESTA" --role=roles/secretmanager.secretAccessor >/dev/null
project_role "$SA_INGESTA" roles/monitoring.viewer
project_role "$SA_INGESTA" roles/logging.logWriter
project_role "$SA_INGESTA" roles/monitoring.metricWriter

# sa-dataflow: worker role, consume its subscription, write only the ecommerce dataset
project_role "$SA_DATAFLOW" roles/dataflow.worker
gcloud pubsub subscriptions add-iam-policy-binding "$SUBSCRIPTION" --project="$PROJECT_ID" \
  --member="serviceAccount:$SA_DATAFLOW" --role=roles/pubsub.subscriber >/dev/null
gcloud pubsub subscriptions add-iam-policy-binding "$SUBSCRIPTION" --project="$PROJECT_ID" \
  --member="serviceAccount:$SA_DATAFLOW" --role=roles/pubsub.viewer >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member="serviceAccount:$SA_DATAFLOW" --role=roles/storage.objectUser >/dev/null
dataset_role "$SA_DATAFLOW" roles/bigquery.dataEditor

# sa-transform: run queries, write only the ecommerce dataset
project_role "$SA_TRANSFORM" roles/bigquery.jobUser
dataset_role "$SA_TRANSFORM" roles/bigquery.dataEditor

# Least privilege: the default Compute Engine SA gets project Editor on creation and nothing uses it any more
# (VM, Dataflow and scheduled queries run as the SAs above)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
  --role=roles/editor --condition=None --quiet >/dev/null 2>&1 || true

echo "IAM OK: $SA_INGESTA, $SA_DATAFLOW, $SA_TRANSFORM; secret kaggle-token; default compute SA without Editor"
