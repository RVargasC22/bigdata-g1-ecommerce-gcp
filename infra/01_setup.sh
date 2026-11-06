#!/usr/bin/env bash
# Bucket (data lake), BigQuery datasets, Pub/Sub, budget. Idempotent.
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

gcloud config set project "$PROJECT_ID" >/dev/null

# Data lake: multi-region US, versioned, lifecycle Standard -> Nearline (30d) -> Coldline (90d)
if ! gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://$BUCKET" --location=US \
    --uniform-bucket-level-access --default-storage-class=STANDARD
fi
gcloud storage buckets update "gs://$BUCKET" --versioning \
  --lifecycle-file=infra/lifecycle.json --update-labels=componente=storage

# Warehouse: multi-region US, 7-day time travel (max)
for ds in "$DATASET" "$DR_DATASET"; do
  bq --location="$BQ_LOCATION" show "$PROJECT_ID:$ds" >/dev/null 2>&1 || \
    bq --location="$BQ_LOCATION" mk --dataset --max_time_travel_hours=168 \
       --label=componente:bigquery "$PROJECT_ID:$ds"
done

# Ingest queue: 7-day retention so a stopped Dataflow job can replay the backlog
gcloud pubsub topics describe "$TOPIC" >/dev/null 2>&1 || \
  gcloud pubsub topics create "$TOPIC" --message-retention-duration=7d \
    --labels=componente=pubsub
gcloud pubsub subscriptions describe "$SUBSCRIPTION" >/dev/null 2>&1 || \
  gcloud pubsub subscriptions create "$SUBSCRIPTION" --topic="$TOPIC" \
    --ack-deadline=60 --message-retention-duration=7d --labels=componente=pubsub

# Budget alerts at 50/90/100 % (billing account currency is PEN)
if ! gcloud billing budgets list --billing-account="$BILLING_ACCOUNT" --account="$BILLING_ADMIN" \
     --format="value(displayName)" 2>/dev/null | grep -qx "presupuesto-$PROJECT_ID"; then
  gcloud billing budgets create --billing-account="$BILLING_ACCOUNT" --account="$BILLING_ADMIN" \
    --display-name="presupuesto-$PROJECT_ID" --budget-amount="${BUDGET_PEN}PEN" \
    --filter-projects="projects/$PROJECT_ID" \
    --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0
fi

echo "Setup OK: gs://$BUCKET, $DATASET, $DR_DATASET, $TOPIC/$SUBSCRIPTION, budget ${BUDGET_PEN} PEN"
