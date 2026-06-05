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

### Backend quality checks

From `backend/`:

```sh
make check
make format
```

`make check` runs Ruff linting, Ruff format checks, and `ty` type checking.
