#!/usr/bin/env bash
# End-to-end test of the Beam job: replays a slice of 17/11/2019 (the peak campaign) at 10x
# from a small VM next to Pub/Sub (the office network blocks gRPC), plus 3 invalid messages for the dead-letter.
# The VM shuts itself down when done; then compare stream vs batch with ecommerce.conciliar_stream.
# Usage: streaming/beam/test_replay.sh [from] [to]   default 2019-11-17 10:00:00 to 10:30:00
#        (with the Beam job already running: streaming/beam/launch.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
source config.env
VM=replay-beam
GS="gs://$BUCKET/replay"
FROM="${1:-2019-11-17 10:00:00}"
TO="${2:-2019-11-17 10:30:00}"

# Slice straight from events_raw (the same rows the batch side counts); the VM sorts it by event_time
bq query --project_id="$PROJECT_ID" --location="$BQ_LOCATION" --use_legacy_sql=false --format=none \
  --maximum_bytes_billed="$MAX_BYTES_BILLED" --label=componente:dataflow <<SQL
EXPORT DATA OPTIONS (uri = '$GS/beam_test-*.csv', format = 'CSV', header = TRUE, overwrite = TRUE) AS
SELECT FORMAT_TIMESTAMP('%F %T UTC', event_time) AS event_time, event_type, product_id, category_id,
  category_code, brand, price, user_id, user_session
FROM $DATASET.events_raw
WHERE event_time >= '$FROM' AND event_time < '$TO'
SQL
gcloud storage cp streaming/producer.py streaming/beam/vm_replay.py "$GS/"

STARTUP=$(mktemp)
trap 'rm -f "$STARTUP"' EXIT
cat > "$STARTUP" <<SH
#!/bin/bash
exec > /var/log/replay.log 2>&1
apt-get -qq update && apt-get -qq install -y python3-venv >/dev/null
python3 -m venv /opt/venv && /opt/venv/bin/pip -q install google-cloud-pubsub
mkdir -p /opt/replay && cd /opt/replay
gcloud storage cp '$GS/producer.py' '$GS/vm_replay.py' '$GS/beam_test-*.csv' .
/opt/venv/bin/python vm_replay.py '$PROJECT_ID' '$TOPIC'
gcloud storage cp /var/log/replay.log '$GS/replay.log'
shutdown -h now
SH

gcloud compute instances create "$VM" --project="$PROJECT_ID" --zone="$ZONE" \
  --machine-type=e2-small --boot-disk-size=10GB --image-family=debian-12 --image-project=debian-cloud \
  --service-account="$SA_INGESTA" --scopes=cloud-platform --labels=componente=ingesta \
  --metadata-from-file=startup-script="$STARTUP"
echo "Replay running on $VM; log at $GS/replay.log when done. Check:"
echo "  SELECT * FROM $DATASET.conciliar_stream('$FROM', '$TO') WHERE NOT coincide"
echo "Then: gcloud compute instances delete $VM --zone=$ZONE, and seek $SUBSCRIPTION to now (the template job"
echo "is stopped and these events are already in events_raw)."
