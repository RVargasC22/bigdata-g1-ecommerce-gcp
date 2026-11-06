#!/usr/bin/env bash
# DRP drill on a disposable copy: accidental DROP -> restore with time travel, then with a snapshot.
# Prints the measured recovery time of each method (RTO evidence). Never touches the real tables.
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env
BQ="bq --project_id=$PROJECT_ID --location=$BQ_LOCATION"
T="$DATASET.drill_fact_pedidos"

$BQ cp --force "$DATASET.fact_pedidos" "$T" >/dev/null
ORIG=$($BQ query --use_legacy_sql=false --format=csv "SELECT COUNT(*) FROM $T" | tail -1)
sleep 5
BEFORE_MS=$(( $(date +%s) * 1000 ))
sleep 5

echo "1) Drop accidental de $T ($ORIG filas)"
$BQ rm -f -t "$T"

echo "2) Restauracion con time travel (tabla borrada: copia desde decorador @ms)"
s=$(date +%s)
$BQ cp "$T@$BEFORE_MS" "$T" >/dev/null
REST=$($BQ query --use_legacy_sql=false --format=csv "SELECT COUNT(*) FROM $T" | tail -1)
echo "   restauradas $REST/$ORIG filas en $(( $(date +%s) - s )) s"

echo "3) Corrupcion: DELETE parcial, restauracion al estado previo (time travel, conserva particion)"
sleep 5
GOOD_MS=$(date +%s%3N)
sleep 5
$BQ query --use_legacy_sql=false "DELETE FROM $T WHERE categoria_comun = 'muebles'" >/dev/null
BAD=$($BQ query --use_legacy_sql=false --format=csv "SELECT COUNT(*) FROM $T" | tail -1)
echo "   tras el DELETE quedan $BAD filas; antes: $($BQ query --use_legacy_sql=false --format=csv \
  "SELECT COUNT(*) FROM $T FOR SYSTEM_TIME AS OF TIMESTAMP_MILLIS($GOOD_MS)" | tail -1)"
s=$(date +%s)
$BQ cp --force "$T@$GOOD_MS" "$T" >/dev/null
REST=$($BQ query --use_legacy_sql=false --format=csv "SELECT COUNT(*) FROM $T" | tail -1)
echo "   restauradas $REST/$ORIG filas en $(( $(date +%s) - s )) s"

echo "4) Restauracion desde snapshot"
SNAP=$($BQ ls --format=json "$DR_DATASET" | python3 -c \
  "import json,sys; ts=[t['tableReference']['tableId'] for t in json.load(sys.stdin) if t['tableReference']['tableId'].startswith('fact_pedidos_')]; print(sorted(ts)[-1] if ts else '')")
if [ -n "$SNAP" ]; then
  $BQ rm -f -t "$T"
  s=$(date +%s)
  $BQ cp --restore --no_clobber "$DR_DATASET.$SNAP" "$T" >/dev/null
  REST=$($BQ query --use_legacy_sql=false --format=csv "SELECT COUNT(*) FROM $T" | tail -1)
  echo "   desde $SNAP: $REST filas en $(( $(date +%s) - s )) s"
else
  echo "   (sin snapshot: correr drp/snapshot.sh primero)"
fi
$BQ rm -f -t "$T"
