#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${DATA_DIR:-$ROOT_DIR/data}"

BAYERN_PBF="$DATA_DIR/bayern.osm.pbf"
BADEN_WUERTTEMBERG_PBF="$DATA_DIR/baden-wuerttemberg.osm.pbf"
MERGED_PBF="$DATA_DIR/by-bw.osm.pbf"
GTFS_ZIP="$DATA_DIR/gtfs-de.zip"
VALHALLA_DATA_DIR="${VALHALLA_DATA_DIR:-$DATA_DIR/valhalla}"
VALHALLA_PBF="$VALHALLA_DATA_DIR/by-bw.osm.pbf"

mkdir -p "$DATA_DIR"
mkdir -p "$VALHALLA_DATA_DIR"

download_if_missing() {
  local url="$1"
  local output="$2"

  if [[ -s "$output" ]]; then
    echo "Keeping existing $(basename "$output")"
    return
  fi

  echo "Downloading $(basename "$output")"
  curl -fL --retry 3 --retry-delay 5 -o "$output" "$url"
}

download_if_missing \
  "https://download.geofabrik.de/europe/germany/bayern-latest.osm.pbf" \
  "$BAYERN_PBF"

download_if_missing \
  "https://download.geofabrik.de/europe/germany/baden-wuerttemberg-latest.osm.pbf" \
  "$BADEN_WUERTTEMBERG_PBF"

download_if_missing \
  "https://download.gtfs.de/germany/free/latest.zip" \
  "$GTFS_ZIP"

echo "Merging Bayern and Baden-Wuerttemberg OSM extracts"
docker run --rm \
  -v "$DATA_DIR:/data" \
  ubuntu:24.04 \
  bash -lc '
    set -euo pipefail
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates osmium-tool
    osmium merge \
      /data/bayern.osm.pbf \
      /data/baden-wuerttemberg.osm.pbf \
      -o /data/by-bw.osm.pbf \
      --overwrite
    chown '"$(id -u):$(id -g)"' /data/by-bw.osm.pbf
  '

echo "Preparing Valhalla OSM extract"
rm -f "$VALHALLA_PBF"
if ! ln "$MERGED_PBF" "$VALHALLA_PBF" 2>/dev/null; then
  cp "$MERGED_PBF" "$VALHALLA_PBF"
fi

echo "Prepared MOTIS data:"
echo "  $MERGED_PBF"
echo "  $GTFS_ZIP"
echo "Prepared Valhalla data:"
echo "  $VALHALLA_PBF"
