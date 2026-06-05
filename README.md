# Questmap

## Backend

Run the FastAPI backend and SurrealDB together:

```sh
docker compose up --build
```

The API is available at `http://localhost:8000`.

- `GET /health` checks the API process.
- `GET /db/health` checks the SurrealDB connection.

SurrealDB is also exposed on `localhost:8001` for local CLI or SDK access.

Default local credentials:

- Username: `root`
- Password: `root`
- Namespace: `questmap`
- Database: `questmap`

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
  rocksdb:.surrealdb-data/questmap.db
```

Or, if you do not have the local `surreal` CLI installed, run SurrealDB through
Docker:

```sh
mkdir -p .surrealdb-data

docker run --rm --pull always \
  -p 8001:8000 \
  -v "$PWD/.surrealdb-data:/data" \
  surrealdb/surrealdb:latest-dev \
  start --user root --pass root rocksdb:/data/questmap.db
```

Then start the backend in another terminal:

```sh
cd backend

SURREALDB_URL=ws://localhost:8001 \
SURREALDB_NAMESPACE=questmap \
SURREALDB_DATABASE=questmap \
SURREALDB_USERNAME=root \
SURREALDB_PASSWORD=root \
uv run fastapi dev main.py --host 0.0.0.0 --port 8000
```

FastAPI runs on `http://localhost:8000`. SurrealDB is mapped to
`localhost:8001` to avoid colliding with the API port.

Check both services:

```sh
curl http://localhost:8000/health
curl http://localhost:8000/db/health
```

### Backend quality checks

From `backend/`:

```sh
make check
make format
```

`make check` runs Ruff linting, Ruff format checks, and `ty` type checking.
