#!/usr/bin/env bash
set -euo pipefail

MOTIS_URL="${MOTIS_URL:-http://localhost:8010}"
ROUTE_TIME="${ROUTE_TIME:-2026-06-06T14:00:00+02:00}"

curl -fsS -G "$MOTIS_URL/api/v6/plan" \
  --data-urlencode "fromPlace=48.7758,9.1829" \
  --data-urlencode "toPlace=48.3984,9.9916" \
  --data-urlencode "time=$ROUTE_TIME" \
  --data-urlencode "transitModes=TRANSIT" \
  --data-urlencode "directModes=" \
  --data-urlencode "preTransitModes=WALK" \
  --data-urlencode "postTransitModes=WALK"
