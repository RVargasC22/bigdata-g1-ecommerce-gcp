#!/usr/bin/env bash
# Runs one or more .sql scripts with a bytes-billed cap and a cost label.
# Usage: sql/run.sh sql/01_ddl.sql [more.sql ...]
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env
# Fills the ${...} account placeholders (sql/15_acceso_filas.sql) so personal accounts stay out of the repo
render() {
  sed -e "s|\${OWNER_ACCOUNT}|$OWNER_ACCOUNT|g" -e "s|\${TEAM_FULL_ACCESS}|$TEAM_FULL_ACCESS|g" \
      -e "s|\${ANALYST_ACCOUNT}|$ANALYST_ACCOUNT|g" -e "s|\${SA_TRANSFORM}|$SA_TRANSFORM|g" "$1"
}
for f in "$@"; do
  echo "== $f"
  render "$f" | bq query --project_id="$PROJECT_ID" --location="$BQ_LOCATION" --use_legacy_sql=false \
    --maximum_bytes_billed="$MAX_BYTES_BILLED" --label=componente:sql \
    --label=script:"$(basename "$f" .sql | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_\n' '_')" \
    --format=pretty --max_rows=100
done
