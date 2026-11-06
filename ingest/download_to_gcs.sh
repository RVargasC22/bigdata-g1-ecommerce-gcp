#!/usr/bin/env bash
# Runs ON the VM. Kaggle -> local disk -> gs://BUCKET/raw/ (original CSVs, gzip-compressed, never modified).
# Also extracts the replay day(s) for the streaming producer.
set -euo pipefail
source ~/app/config.env
KAGGLE=~/venv/bin/kaggle
WORK=~/data; mkdir -p "$WORK"/{rees46,olist,replay}; cd "$WORK"

echo "== REES46 files on Kaggle:"; $KAGGLE datasets files "$KAGGLE_REES46"
$KAGGLE datasets download "$KAGGLE_REES46" -p rees46 --unzip
for f in rees46/*.csv; do
  pigz -f "$f"
  gcloud storage cp "$f.gz" "gs://$BUCKET/raw/rees46/"
done

# Kaggle stops at November (20 GB limit); the dataset description points to the author's mirror for December.
# Jan-Mar 2020 from the same mirror: real holdout for the demand forecast (sql/16_forecast.sql).
for m in 2019-Dec 2020-Jan 2020-Feb 2020-Mar; do
  curl -sSf -o "rees46/$m.csv.gz" "https://data.rees46.com/datasets/marketplace/$m.csv.gz"
  gcloud storage cp "rees46/$m.csv.gz" "gs://$BUCKET/raw/rees46/"
done

$KAGGLE datasets download "$KAGGLE_OLIST" -p olist --unzip
gcloud storage cp olist/*.csv "gs://$BUCKET/raw/olist/"

# Replay files: one per streamed day, header kept, in event_time order
HEADER="event_time,event_type,product_id,category_id,category_code,brand,price,user_id,user_session"
for day in 2019-11-17 2019-11-29 2019-12-02; do
  src=$(ls rees46/*.csv.gz | grep -E "2019-$(LC_ALL=C date -d "$day" +%b)" || true)
  [ -z "$src" ] && { echo "WARN: no source file for $day (not in Kaggle dataset)"; continue; }
  out=replay/rees46_$day.csv
  { echo "$HEADER"; pigz -dc "$src" | grep "^$day " | LC_ALL=C sort -s -t, -k1,1; } > "$out"
  echo "$out: $(($(wc -l < "$out") - 1)) events"
  gcloud storage cp "$out" "gs://$BUCKET/replay/"
done
gcloud storage ls -l "gs://$BUCKET/raw/**" | tail -20
