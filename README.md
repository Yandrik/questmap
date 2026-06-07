# Meander

## Backend

Run the FastAPI backend and SurrealDB together:

```sh
docker compose up --build
```

The API is available at `http://localhost:8000`.

- `GET /health` checks the API process.
- `GET /db/health` checks the SurrealDB connection.
- `GET /routing/health` checks the Valhalla routing service.
- `POST /routing/route` proxies typed Valhalla `/route` requests.
- `GET /transit/health` checks the MOTIS transit routing service.
- `POST /transit/plan` proxies typed MOTIS `/api/v6/plan` requests.
- `POST /trip-planning/sessions` starts a durable routed trip-planning run.
- `GET /trip-planning/sessions/{sessionId}` returns a resumable session snapshot.
- `GET /trip-planning/sessions/{sessionId}/events` streams planning SSE events.
- `POST /trip-planning/sessions/{sessionId}/answers` answers agent questions.
- `POST /trip-planning/sessions/{sessionId}/cancel` cancels a running session.

SurrealDB is also exposed on `localhost:8001` for local CLI or SDK access.
Valhalla is exposed on `localhost:8002` for direct routing API access.
MOTIS is exposed on `localhost:8010` for direct transit routing API access.

Default local credentials:

- Username: `root`
- Password: `root`
- Namespace: `meander`
- Database: `meander`

### Valhalla and MOTIS data

The root Docker Compose stack prepares routing data through the `motis-data`
service and stores it in persistent Docker volumes:

- `motis-data`: OSM, GTFS, and imported MOTIS files.
- `valhalla-data`: the OSM extract and generated Valhalla graph files.

This is the preferred deployment path for Coolify because it avoids nested
Docker bind mounts during the build. First deployment can take a while; later
deployments reuse the volumes and skip the heavy download/import work.

For a manual one-shot data preparation run:

```sh
./prepare.sh
```

To force a fresh OSM/GTFS download and MOTIS import:

```sh
FORCE_DATA_REFRESH=true ./prepare.sh
```

Then start the stack:

```sh
docker compose up -d --build
```

### Valhalla routing

Docker Compose runs `ghcr.io/valhalla/valhalla-scripted:latest` and mounts
the persistent `valhalla-data` volume at `/custom_files`. The `motis-data`
service prepares the Bayern + Baden-Wuerttemberg extract before Valhalla starts:

```sh
docker compose up valhalla
curl http://localhost:8002/status
```

The data service downloads the Bayern and Baden-Wuerttemberg Geofabrik
extracts, merges them into `by-bw.osm.pbf`, and hard-links or copies that
merged PBF into the Valhalla data volume. The scripted Valhalla image builds
graph tiles from that local PBF and stores its generated files next to it.

To route somewhere else, change the OSM URLs in the data-prep script and force a
data refresh. Using one local merged PBF in the Valhalla volume is preferred
over Valhalla's multi-URL build mode.

```sh
VALHALLA_TILE_URLS=https://download.geofabrik.de/europe/germany/berlin-latest.osm.pbf \
  docker compose up --build
```

Useful Valhalla settings are exposed through Compose variables:

- `VALHALLA_TILE_URLS`: one or more space-separated `.osm.pbf` URLs.
- `VALHALLA_SERVER_THREADS`: tile build and service thread count, default `2`.
- `VALHALLA_BUILD_ELEVATION`: set `True` or `Force` to include elevation data.
- `VALHALLA_USE_TILES_IGNORE_PBF`: defaults to `True`, so existing tiles are
  preferred when available.

The backend reads `VALHALLA_URL` and defaults to `http://localhost:8002` outside
Compose. The Python integration uses `httpx` with Pydantic request models
mirroring the Valhalla OpenAPI `/route` schema. The Flutter app uses `dio` with
matching Dart request models under `app/lib/features/routing/`. The OpenAPI
source used for reference is checked in at `openapi/valhalla.openapi.yaml`.

### MOTIS transit routing

Docker Compose also runs the local MOTIS image from `motis/`, using the
persistent `motis-data` volume as its read-only data directory:

```sh
docker compose up motis
curl http://localhost:8010/api/v1/health
```

The `motis-data` service imports MOTIS data before the MOTIS server starts. The
backend reads `MOTIS_URL` and defaults to `http://localhost:8010` outside
Compose. The Python integration uses `httpx` with a Pydantic request model
mirroring the MOTIS OpenAPI `/api/v6/plan` query schema. The Flutter app uses
`dio` with matching Dart request models under `app/lib/features/transit/`. The
OpenAPI source used for reference is checked in at
`openapi/motis.openapi.yaml`.

### Local development

To run SurrealDB and the Python backend locally without Docker Compose, start a
SurrealDB server first.

With the local SurrealDB CLI:

```sh
mkdir -p .surrealdb-data

surreal start \
  --bind 127.0.0.1:8001 \
  --user root \
  --pass root \
  rocksdb:.surrealdb-data/meander.db
```

Or, if you do not have the local `surreal` CLI installed, run SurrealDB through
Docker:

```sh
mkdir -p .surrealdb-data

docker run --rm --pull always \
  -p 8001:8000 \
  -v "$PWD/.surrealdb-data:/data" \
  surrealdb/surrealdb:latest-dev \
  start --user root --pass root rocksdb:/data/meander.db
```

Then start the backend in another terminal:

```sh
cd backend

SURREALDB_URL=ws://localhost:8001 \
SURREALDB_NAMESPACE=meander \
SURREALDB_DATABASE=meander \
SURREALDB_USERNAME=root \
SURREALDB_PASSWORD=root \
VALHALLA_URL=http://localhost:8002 \
MOTIS_URL=http://localhost:8010 \
uv run fastapi dev main.py --host 0.0.0.0 --port 8000
```

FastAPI runs on `http://localhost:8000`. SurrealDB is mapped to
`localhost:8001` to avoid colliding with the API port.

Check both services:

```sh
curl http://localhost:8000/health
curl http://localhost:8000/db/health
curl http://localhost:8000/routing/health
curl http://localhost:8000/transit/health
```

### Backend quality checks

From `backend/`:

```sh
make check
make format
```

`make check` runs Ruff linting, Ruff format checks, and `ty` type checking.
