#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
VALHALLA_DATA_DIR="${VALHALLA_DATA_DIR:-/valhalla}"
CONFIG_SOURCE="${MOTIS_CONFIG_SOURCE:-/opt/questmap/motis-config.yml}"
KEEP_ALIVE="${DATA_SERVICE_KEEP_ALIVE:-true}"
FORCE_REFRESH="${FORCE_DATA_REFRESH:-false}"

BAYERN_PBF="$DATA_DIR/bayern.osm.pbf"
BADEN_WUERTTEMBERG_PBF="$DATA_DIR/baden-wuerttemberg.osm.pbf"
MERGED_PBF="$DATA_DIR/by-bw.osm.pbf"
GTFS_ZIP="$DATA_DIR/gtfs-de.zip"
VALHALLA_PBF="$VALHALLA_DATA_DIR/by-bw.osm.pbf"
MOTIS_IMPORTED_MARKER="$DATA_DIR/.motis-imported"
VALHALLA_PREPARED_MARKER="$VALHALLA_DATA_DIR/.valhalla-prepared"

is_true() {
  case "${1,,}" in
    1 | true | yes | y | force) return 0 ;;
    *) return 1 ;;
  esac
}

download_if_missing() {
  local url="$1"
  local output="$2"

  if [[ -s "$output" ]] && ! is_true "$FORCE_REFRESH"; then
    echo "Keeping existing $(basename "$output")"
    return
  fi

  rm -f "$output"
  echo "Downloading $(basename "$output")"
  curl -fL --retry 3 --retry-delay 5 -o "$output" "$url"
}

mkdir -p "$DATA_DIR" "$VALHALLA_DATA_DIR"
cp "$CONFIG_SOURCE" "$DATA_DIR/config.yml"

download_if_missing \
  "https://download.geofabrik.de/europe/germany/bayern-latest.osm.pbf" \
  "$BAYERN_PBF"

download_if_missing \
  "https://download.geofabrik.de/europe/germany/baden-wuerttemberg-latest.osm.pbf" \
  "$BADEN_WUERTTEMBERG_PBF"

download_if_missing \
  "https://download.gtfs.de/germany/free/latest.zip" \
  "$GTFS_ZIP"

if [[ ! -s "$MERGED_PBF" ]] || is_true "$FORCE_REFRESH"; then
  echo "Merging Bayern and Baden-Wuerttemberg OSM extracts"
  rm -f "$MERGED_PBF"
  osmium merge \
    "$BAYERN_PBF" \
    "$BADEN_WUERTTEMBERG_PBF" \
    -o "$MERGED_PBF" \
    --overwrite
else
  echo "Keeping existing $(basename "$MERGED_PBF")"
fi

if [[ ! -s "$VALHALLA_PBF" ]] || is_true "$FORCE_REFRESH"; then
  echo "Preparing Valhalla OSM extract"
  rm -f "$VALHALLA_PBF"
  if ! ln "$MERGED_PBF" "$VALHALLA_PBF" 2>/dev/null; then
    cp "$MERGED_PBF" "$VALHALLA_PBF"
  fi
else
  echo "Keeping existing Valhalla OSM extract"
fi
touch "$VALHALLA_PREPARED_MARKER"

if [[ ! -f "$MOTIS_IMPORTED_MARKER" ]] || is_true "$FORCE_REFRESH"; then
  echo "Importing MOTIS data"
  rm -f "$MOTIS_IMPORTED_MARKER"
  (
    cd "$DATA_DIR"
    /motis import --data "$DATA_DIR" --config "$DATA_DIR/config.yml"
  )
  touch "$MOTIS_IMPORTED_MARKER"
else
  echo "Keeping existing MOTIS import"
fi

echo "MOTIS data is ready in $DATA_DIR"
echo "Valhalla data is ready in $VALHALLA_DATA_DIR"

if is_true "$KEEP_ALIVE"; then
  echo "Keeping data service alive for Compose/Coolify health checks"
  tail -f /dev/null
fi
