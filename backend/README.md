# Backend

FastAPI backend for main, using SurrealDB as the database via `surrealdb-orm`.

## Migrations

Migrations track schema changes to SurrealDB tables. They are stored in the `migrations/` directory and applied automatically on startup via `MigrationExecutor`.

### Creating a new migration

**1. Update your models in `models.py`** — add, remove, or alter fields/tables as needed.

**2. Generate the migration file** by running `makemigrations` against the live database so the tool can diff the current schema:

```bash
surreal-orm makemigrations --name <short_description> \
  --url http://localhost:8001 \
  --namespace main \
  --database main \
  --user root \
  --password root
```

Using environment variables instead:

```bash
export SURREAL_URL=http://localhost:8001
export SURREAL_NAMESPACE=main
export SURREAL_DATABASE=main
export SURREAL_USER=root
export SURREAL_PASSWORD=root

surreal-orm makemigrations --name <short_description>
```

> Port `8001` maps to the SurrealDB container (see `docker-compose.yml`).

This creates `migrations/<next_number>_<short_description>.py`. **Review the generated file before applying it.**

**3. For manual/custom changes**, generate an empty migration and edit it by hand:

```bash
surreal-orm makemigrations --name <short_description> --empty
```

Then add operations such as `RawSQL` or `DataMigration` to the generated file.

### Applying migrations

Migrations are applied automatically when the backend starts. To apply them manually:

```bash
surreal-orm migrate \
  --url http://localhost:8001 \
  --namespace main \
  --database main \
  --user root \
  --password root
```

### Other useful commands

| Command | Purpose |
|---|---|
| `surreal-orm status ...` | Show which migrations are applied / pending |
| `surreal-orm sqlmigrate <name> ...` | Preview the SQL a migration will run |
| `surreal-orm rollback <name> ...` | Roll back to a specific migration |
| `surreal-orm upgrade ...` | Apply data migrations (`DataMigration` operations) |

### Best practices

- Keep each migration focused on one logical change.
- Use `DataMigration` for record transformations, not schema changes.
- Test migrations against a staging database before running in production.
- Back up the database before applying migrations in production.
