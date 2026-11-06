#!/usr/bin/env bash
# Email channel + every alert policy in monitoring/alert_*.json. Idempotent by display name.
#   alert_system_lag       Dataflow behind (RPO < 5 min at risk)
#   alert_pubsub_backlog   data freshness: messages waiting > 10 min (job down or stuck)
#   alert_scheduled_query  daily refresh or data-quality ASSERT failed (sql/17, sql/18), incl. dead-letter growth
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

CH=$(gcloud beta monitoring channels list --project="$PROJECT_ID" \
      --filter="labels.email_address=\"$ALERT_EMAIL\"" --format="value(name)" | head -1)
if [ -z "$CH" ]; then
  CH=$(gcloud beta monitoring channels create --project="$PROJECT_ID" --display-name="Grupo 1 email" \
        --type=email --channel-labels=email_address="$ALERT_EMAIL" --format="value(name)")
fi
EXISTING=$(gcloud monitoring policies list --project="$PROJECT_ID" --format="value(displayName)")
for f in monitoring/alert_*.json; do
  NAME=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["displayName"])' "$f")
  if ! grep -qxF "$NAME" <<<"$EXISTING"; then
    gcloud monitoring policies create --project="$PROJECT_ID" --policy-from-file="$f" \
      --notification-channels="$CH" --format="value(name)"
  fi
done
echo "Alerts OK -> $ALERT_EMAIL"
