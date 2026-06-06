from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Request
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from surrealdb import AsyncSurreal, RecordID, SurrealError

from motis import MotisClient, MotisPlanRequest
from schemas import (
    ActivityResponse,
    DatabaseHealthResponse,
    GeoPoint,
    HealthResponse,
    TripCreate,
    TripResponse,
)
from valhalla import ValhallaClient, ValhallaRouteRequest


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="SURREALDB_", case_sensitive=False, env_file=".env", extra="ignore"
    )

    url: str = Field(default="ws://localhost:8000")
    namespace: str = Field(default="questmap")
    database: str = Field(default="questmap")
    username: str = Field(default="root")
    password: str = Field(default="root")


class ValhallaSettings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="VALHALLA_", case_sensitive=False, env_file=".env", extra="ignore"
    )

    url: str = Field(default="http://localhost:8002")


class MotisSettings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="MOTIS_", case_sensitive=False, env_file=".env", extra="ignore"
    )

    url: str = Field(default="http://localhost:8080")



_SCHEMA_SQL = """
DEFINE TABLE IF NOT EXISTS trip SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS start_time ON trip TYPE datetime;
DEFINE FIELD IF NOT EXISTS start_location ON trip TYPE string;
DEFINE FIELD IF NOT EXISTS end_time ON trip TYPE datetime;
DEFINE FIELD IF NOT EXISTS end_location ON trip TYPE string;
DEFINE FIELD IF NOT EXISTS activities ON trip TYPE array;
DEFINE FIELD IF NOT EXISTS activities[*] ON trip TYPE object;
DEFINE FIELD IF NOT EXISTS activities[*].type ON trip TYPE string;
DEFINE FIELD IF NOT EXISTS activities[*].duration_minutes ON trip TYPE int;
DEFINE FIELD IF NOT EXISTS activities[*].specification ON trip TYPE option<string>;
"""



@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = Settings()
    valhalla_settings = ValhallaSettings()
    motis_settings = MotisSettings()
    db = AsyncSurreal(settings.url)

    await db.connect(settings.url)
    await db.use(settings.namespace, settings.database)
    await db.signin(
        {
            "username": settings.username,
            "password": settings.password,
        }
    )
    await db.query(_SCHEMA_SQL)

    app.state.settings = settings
    app.state.valhalla_settings = valhalla_settings
    app.state.motis_settings = motis_settings
    app.state.db = db
    app.state.valhalla = ValhallaClient(valhalla_settings.url)
    app.state.motis = MotisClient(motis_settings.url)

    try:
        yield
    finally:
        await app.state.motis.close()
        await app.state.valhalla.close()
        await db.close()


app = FastAPI(title="Questmap API", lifespan=lifespan)


class RoutingHealthResponse(HealthResponse):
    url: str
    upstream: dict[str, Any]


class TransitHealthResponse(HealthResponse):
    url: str
    upstream: dict[str, Any]



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
        url=settings.url,
        namespace=settings.namespace,
        database=settings.database,
    )


@app.get("/routing/health")
async def routing_health(request: Request) -> RoutingHealthResponse:
    valhalla_settings: ValhallaSettings = request.app.state.valhalla_settings

    try:
        upstream = await request.app.state.valhalla.status()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Valhalla is unavailable") from exc

    return RoutingHealthResponse(
        status="ok",
        url=valhalla_settings.url,
        upstream=upstream,
    )


@app.post("/routing/route")
async def route(body: ValhallaRouteRequest, request: Request) -> dict[str, Any]:
    try:
        return await request.app.state.valhalla.route(body)
    except httpx.HTTPStatusError as exc:
        status_code = exc.response.status_code
        if status_code in {400, 429}:
            raise HTTPException(
                status_code=status_code, detail=exc.response.text
            ) from exc
        raise HTTPException(status_code=502, detail="Valhalla route failed") from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Valhalla route failed") from exc


@app.get("/transit/health")
async def transit_health(request: Request) -> TransitHealthResponse:
    motis_settings: MotisSettings = request.app.state.motis_settings

    try:
        upstream = await request.app.state.motis.health()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="MOTIS is unavailable") from exc

    return TransitHealthResponse(
        status="ok",
        url=motis_settings.url,
        upstream=upstream,
    )


@app.post("/transit/plan")
async def transit_plan(body: MotisPlanRequest, request: Request) -> dict[str, Any]:
    try:
        return await request.app.state.motis.plan(body)
    except httpx.HTTPStatusError as exc:
        status_code = exc.response.status_code
        if status_code in {400, 404, 422, 429}:
            raise HTTPException(
                status_code=status_code, detail=exc.response.text
            ) from exc
        raise HTTPException(status_code=502, detail="MOTIS plan failed") from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail="MOTIS plan failed") from exc


# ---------------------------------------------------------------------------
# Trips
# ---------------------------------------------------------------------------


def _to_geo(raw) -> GeoPoint:
    """Convert a SurrealDB geometry<point> value to GeoPoint."""
    coords = raw["coordinates"] if isinstance(raw, dict) else raw.coordinates
    return GeoPoint(lon=coords[0], lat=coords[1])


def _from_geo(p: GeoPoint) -> dict:
    """Convert a GeoPoint to a GeoJSON Point dict for SurrealDB."""
    return {"type": "Point", "coordinates": [p.lon, p.lat]}


def _trip_to_response(raw: dict) -> TripResponse:
    return TripResponse(
        id=str(raw["id"].id),
        start_time=raw["start_time"],
        start_location=_to_geo(raw["start_location"]),
        end_time=raw["end_time"],
        end_location=_to_geo(raw["end_location"]),
        activities=[
            ActivityResponse(
                type=a["type"],
                duration_minutes=a["duration_minutes"],
                specification=a.get("specification"),
            )
            for a in raw.get("activities", [])
        ],
    )


@app.post("/trips", status_code=201)
async def create_trip(body: TripCreate, request: Request) -> TripResponse:
    raw = await request.app.state.db.create(
        "trip",
        {
            "start_time": body.start_time,
            "start_location": _from_geo(body.start_location),
            "end_time": body.end_time,
            "end_location": _from_geo(body.end_location),
            "activities": [
                {
                    "type": a.type,
                    "duration_minutes": a.duration_minutes,
                    "specification": a.specification,
                }
                for a in body.activities
            ],
        },
    )
    return _trip_to_response(raw)


@app.get("/trips")
async def list_trips(request: Request) -> list[TripResponse]:
    raws = await request.app.state.db.select("trip") or []
    return [_trip_to_response(r) for r in raws]


@app.get("/trips/{trip_id}")
async def get_trip(trip_id: str, request: Request) -> TripResponse:
    raw = await request.app.state.db.select(RecordID("trip", trip_id))
    if raw is None:
        raise HTTPException(status_code=404, detail="Trip not found")
    return _trip_to_response(raw)
