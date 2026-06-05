import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel, Field
from surrealdb import AsyncSurreal, SurrealError


class Settings(BaseModel):
    surrealdb_url: str = Field(default="ws://localhost:8000")
    surrealdb_namespace: str = Field(default="questmap")
    surrealdb_database: str = Field(default="questmap")
    surrealdb_username: str = Field(default="root")
    surrealdb_password: str = Field(default="root")


def load_settings() -> Settings:
    return Settings(
        surrealdb_url=os.getenv("SURREALDB_URL", "ws://localhost:8000"),
        surrealdb_namespace=os.getenv("SURREALDB_NAMESPACE", "questmap"),
        surrealdb_database=os.getenv("SURREALDB_DATABASE", "questmap"),
        surrealdb_username=os.getenv("SURREALDB_USERNAME", "root"),
        surrealdb_password=os.getenv("SURREALDB_PASSWORD", "root"),
    )


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = load_settings()
    db = AsyncSurreal(settings.surrealdb_url)

    await db.connect(settings.surrealdb_url)
    await db.use(settings.surrealdb_namespace, settings.surrealdb_database)
    await db.signin(
        {
            "username": settings.surrealdb_username,
            "password": settings.surrealdb_password,
        }
    )

    app.state.settings = settings
    app.state.db = db

    try:
        yield
    finally:
        await db.close()


app = FastAPI(title="Questmap API", lifespan=lifespan)


class HealthResponse(BaseModel):
    status: str


class DatabaseHealthResponse(HealthResponse):
    url: str
    namespace: str
    database: str


@app.get("/health")
async def health() -> HealthResponse:
    return HealthResponse(status="ok")


@app.get("/db/health")
async def database_health(request: Request) -> DatabaseHealthResponse:
    settings: Settings = request.app.state.settings

    try:
        await request.app.state.db.query("RETURN true;")
    except SurrealError as exc:
        raise HTTPException(status_code=503, detail="SurrealDB is unavailable") from exc

    return DatabaseHealthResponse(
        status="ok",
        url=settings.surrealdb_url,
        namespace=settings.surrealdb_namespace,
        database=settings.surrealdb_database,
    )
