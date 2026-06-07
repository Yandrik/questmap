#!/usr/bin/env bash
set -euo pipefail

DATA_SERVICE_KEEP_ALIVE=false docker compose run --rm motis-data
