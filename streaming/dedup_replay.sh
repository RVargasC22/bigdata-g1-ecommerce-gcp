#!/usr/bin/env bash
# Cleans up after replaying a window that is already in events_raw while the template job was running
# (Pub/Sub delivers at least once and the template does not deduplicate, so those events get inserted twice).
#  1. events_raw: keeps the first copy of each identical event in [FROM, TO) (ordered by ingest_time).
#  2. stream_categoria_minuto: deletes the Beam rows written since SINCE (optional). Run this step about
#     1 hour after the Beam job stopped: rows inserted with streaming inserts block DML until the buffer flushes.
# Usage: streaming/dedup_replay.sh "2019-11-17 10:30:00" "2019-11-17 11:00:00" [2026-11-12]
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env
FROM="${1:?usage: dedup_replay.sh FROM TO [SINCE]}"
TO="${2:?usage: dedup_replay.sh FROM TO [SINCE]}"
SINCE="${3:-}"
DAY="${FROM%% *}"
BQ="bq --project_id=$PROJECT_ID --location=$BQ_LOCATION query --use_legacy_sql=false --maximum_bytes_billed=$MAX_BYTES_BILLED"
WINDOW="DATE(event_time) = '$DAY' AND event_time >= '$FROM' AND event_time < '$TO'"

$BQ "SELECT COUNT(*) AS rows_before, COUNT(DISTINCT TO_JSON_STRING(t)) AS distinct_events FROM (
  SELECT * EXCEPT (ingest_time) FROM $DATASET.events_raw WHERE $WINDOW) t"

$BQ "BEGIN
  CREATE TEMP TABLE w AS
  SELECT * EXCEPT (rn) FROM (
    SELECT *, ROW_NUMBER() OVER (
      PARTITION BY event_time, event_type, product_id, category_id, category_code, brand, price, user_id,
                   user_session, source ORDER BY ingest_time) AS rn
    FROM $DATASET.events_raw WHERE $WINDOW)
  WHERE rn = 1;
  DELETE FROM $DATASET.events_raw WHERE $WINDOW;
  INSERT INTO $DATASET.events_raw SELECT * FROM w;
  SELECT COUNT(*) AS rows_after FROM $DATASET.events_raw WHERE $WINDOW;
END"

if [ -n "$SINCE" ]; then
  $BQ "DELETE FROM $DATASET.stream_categoria_minuto WHERE procesado_en >= TIMESTAMP('$SINCE')"
fi
echo "Dedup OK for [$FROM, $TO)"
