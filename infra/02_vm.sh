#!/usr/bin/env bash
# Temporary VM next to Pub/Sub: downloads Kaggle data straight into the bucket and runs the replay producer.
# Delete it with infra/99_teardown.sh when finished.
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

if ! gcloud compute instances describe "$VM_NAME" --zone="$ZONE" >/dev/null 2>&1; then
  gcloud compute instances create "$VM_NAME" --zone="$ZONE" \
    --machine-type=e2-standard-4 --boot-disk-size=200GB --boot-disk-type=pd-standard \
    --image-family=debian-12 --image-project=debian-cloud \
    --service-account="$SA_INGESTA" --scopes=cloud-platform \
    --labels=componente=ingesta
  echo "Waiting for SSH..."; sleep 30
fi

gcloud compute ssh "$VM_NAME" --zone="$ZONE" --tunnel-through-iap --command="mkdir -p ~/app ~/.kaggle"
gcloud compute scp --zone="$ZONE" --tunnel-through-iap --recurse config.env ingest streaming monitoring "$VM_NAME":~/app/
# Kaggle token comes from Secret Manager (sa-ingesta can read only that secret); nothing is copied from the laptop
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --tunnel-through-iap --command="umask 077 && \
  gcloud secrets versions access latest --secret=kaggle-token --project=$PROJECT_ID > ~/.kaggle/access_token && \
  sudo apt-get -qq update && sudo apt-get -qq install -y python3-venv unzip pigz >/dev/null && \
  python3 -m venv ~/venv && ~/venv/bin/pip -q install kaggle six google-cloud-pubsub google-cloud-monitoring"
echo "VM ready. Next: gcloud compute ssh $VM_NAME --zone=$ZONE -- 'bash ~/app/ingest/download_to_gcs.sh'"
