from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Request
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from surrealdb import AsyncSurreal, RecordID

from db import SurrealConnection, dict_to_route, dict_to_trip, init_db
from models import Activity, Route, Trip
from models import RouteStep as RouteStepModel
from motis import MotisClient, MotisPlanRequest
from schemas import (
    ActivityResponse,
    DatabaseHealthResponse,
    HealthResponse,
    RouteCreate,
    RouteResponse,
    TripCreate,
    TripResponse,
)
from valhalla import ValhallaClient, ValhallaRouteRequest


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="SURREALDB_", case_sensitive=False, env_file=".env", extra="ignore"
    )

    url: str = Field(default="http://localhost:8000")
    namespace: str = Field(default="main")
    database: str = Field(default="main")
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

    url: str = Field(default="http://localhost:8010")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = Settings()
    valhalla_settings = ValhallaSettings()
    motis_settings = MotisSettings()

    app.state.settings = settings
    app.state.valhalla_settings = valhalla_settings
    app.state.motis_settings = motis_settings
    app.state.valhalla = ValhallaClient(valhalla_settings.url)
    app.state.motis = MotisClient(motis_settings.url)

    async with AsyncSurreal(settings.url) as db:
        await db.signin({"username": settings.username, "password": settings.password})
        await db.use(settings.namespace, settings.database)
        await init_db(db)
        app.state.db = db

        try:
            yield
        finally:
            await app.state.motis.close()
            await app.state.valhalla.close()


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
    db = request.app.state.db

    try:
        await db.query("RETURN true;")
    except Exception as exc:
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


def _trip_to_response(trip: Trip) -> TripResponse:
    return TripResponse(
        id=trip.id or "",
        start_time=trip.start_time,
        start_location=trip.start_location,
        end_time=trip.end_time,
        end_location=trip.end_location,
        activities=[
            ActivityResponse(
                type=a.type,
                duration_minutes=a.duration_minutes,
                specification=a.specification,
            )
            for a in trip.activities
        ],
    )


@app.post("/trips", status_code=201)
async def create_trip(body: TripCreate, request: Request) -> TripResponse:
    db = request.app.state.db
    result = await db.create("trip", {
        "start_time": body.start_time,
        "start_location": body.start_location,
        "end_time": body.end_time,
        "end_location": body.end_location,
        "activities": [a.model_dump() for a in body.activities],
    })
    trip = dict_to_trip(result[0] if isinstance(result, list) else result)
    return _trip_to_response(trip)


@app.get("/trips")
async def list_trips(request: Request) -> list[TripResponse]:
    db = request.app.state.db
    result = await db.select("trip")
    return [_trip_to_response(dict_to_trip(r)) for r in (result or [])]


@app.get("/trips/{trip_id}")
async def get_trip(trip_id: str, request: Request) -> TripResponse:
    db = request.app.state.db
    result = await db.select(RecordID("trip", trip_id))
    if result is None:
        raise HTTPException(status_code=404, detail="Trip not found")
    return _trip_to_response(dict_to_trip(result))


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


def _route_to_response(route_obj: Route) -> RouteResponse:
    return RouteResponse(
        id=route_obj.id or "",
        name=route_obj.name,
        trip_id=route_obj.trip_id,
        steps=[s.model_dump() for s in route_obj.steps],
    )


@app.post("/routes", status_code=201)
async def create_route(body: RouteCreate, request: Request) -> RouteResponse:
    db = request.app.state.db
    result = await db.create("route", {
        "name": body.name,
        "trip_id": body.trip_id,
        "steps": [s.model_dump(mode="json") for s in body.steps],
    })
    route_obj = dict_to_route(result[0] if isinstance(result, list) else result)
    return _route_to_response(route_obj)


@app.get("/routes")
async def list_routes(request: Request) -> list[RouteResponse]:
    db = request.app.state.db
    result = await db.select("route")
    return [_route_to_response(dict_to_route(r)) for r in (result or [])]


@app.get("/routes/{route_id}")
async def get_route(route_id: str, request: Request) -> RouteResponse:
    db = request.app.state.db
    result = await db.select(RecordID("route", route_id))
    if result is None:
        raise HTTPException(status_code=404, detail="Route not found")
    return _route_to_response(dict_to_route(result))
