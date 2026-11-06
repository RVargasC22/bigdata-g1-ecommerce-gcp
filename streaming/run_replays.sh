#!/usr/bin/env bash
# Runs ON the VM. Replays the streamed days in sequence; logs start/end times to line up with Monitoring.
# Usage: nohup bash ~/app/streaming/run_replays.sh > ~/replays.log 2>&1 &
set -euo pipefail
source ~/app/config.env
run() {
  local day="$1" speed="$2"
  echo "START $day speedup=$speed $(date -u +%FT%TZ)"
  ~/venv/bin/python ~/app/streaming/producer.py ~/data/replay/rees46_"$day".csv \
    --project "$PROJECT_ID" --topic "$TOPIC" --speedup "$speed"
  echo "END $day $(date -u +%FT%TZ)"
}
run 2019-12-02 60
run 2019-11-29 60
run 2019-11-17 10
