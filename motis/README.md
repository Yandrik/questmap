# Questmap MOTIS

Self-hosted MOTIS setup for public-transit routing. The current data scope is:

- OpenStreetMap: Bayern + Baden-Wuerttemberg Geofabrik extracts, merged into one PBF.
- Timetable: GTFS.DE Germany Full static feed.
- Realtime: GTFS.DE matching GTFS-RT feed configured in `data/config.yml`.

The app/backend should restrict user requests to Bayern + Baden-Wuerttemberg for now. Keeping Germany-wide GTFS preserves boundary and long-distance trips while the OSM street graph remains regional.

## Build

```sh
cd motis
docker compose build
```

For ARM64:

```sh
cd motis
MOTIS_TARGETARCH=arm64 docker compose build
```

## Prepare Data

This downloads the two Geofabrik OSM extracts, downloads GTFS.DE Germany Full,
merges the OSM extracts into `data/by-bw.osm.pbf`, and prepares
`data/valhalla/by-bw.osm.pbf` for the root Docker Compose Valhalla service.

```sh
cd motis
./scripts/prepare-by-bw-data.sh
```

Inputs are kept if they already exist. Remove files from `data/` to force a fresh download.

## Import

```sh
cd motis
./scripts/import.sh
```

This runs `motis import --data /data --config /data/config.yml` against `./data`. Do not overwrite files in `./data` while a MOTIS server is running. For production updates, import into a staging directory and swap directories while the service is stopped.

## Run

```sh
cd motis
docker compose up -d motis
```

MOTIS is exposed on `http://localhost:8010` by default. Override with `MOTIS_PORT`:

```sh
MOTIS_PORT=8081 docker compose up -d motis
```

## Smoke Test

After import and startup:

```sh
curl http://localhost:8010/
./scripts/test-plan.sh
```

The plan script checks a Stuttgart to Ulm public-transit route using `/api/v6/plan`.

## Backend Guard

Use a backend guard before proxying to MOTIS:

```ts
const BY_BW_BBOX = {
  minLat: 47.25,
  maxLat: 50.75,
  minLon: 7.35,
  maxLon: 13.85,
};

function insideByBw(lat: number, lon: number) {
  return (
    lat >= BY_BW_BBOX.minLat &&
    lat <= BY_BW_BBOX.maxLat &&
    lon >= BY_BW_BBOX.minLon &&
    lon <= BY_BW_BBOX.maxLon
  );
}
```

Use actual state polygons before exposing this publicly.
