from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Request
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from surreal_orm import SurrealDBConnectionManager
from surreal_orm.connection_manager import SurrealDbConnectionError
from surreal_orm.migrations.executor import MigrationExecutor

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

    SurrealDBConnectionManager.set_connection(
        url=settings.url,
        user=settings.username,
        password=settings.password,
        namespace=settings.namespace,
        database=settings.database,
    )

    app.state.settings = settings
    app.state.valhalla_settings = valhalla_settings
    app.state.motis_settings = motis_settings
    app.state.valhalla = ValhallaClient(valhalla_settings.url)
    app.state.motis = MotisClient(motis_settings.url)

    migrations = MigrationExecutor(Path(__file__).parent / "migrations")
    await migrations.migrate()

    try:
        yield
    finally:
        await app.state.motis.close()
        await app.state.valhalla.close()
        await SurrealDBConnectionManager.close_connection()


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
        async with SurrealDBConnectionManager() as client:
            await client.query("RETURN true;")
    except SurrealDbConnectionError as exc:
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
async def create_trip(body: TripCreate) -> TripResponse:
    trip = Trip(
        start_time=body.start_time,
        start_location=body.start_location,
        end_time=body.end_time,
        end_location=body.end_location,
        activities=[
            Activity(
                type=a.type,
                duration_minutes=a.duration_minutes,
                specification=a.specification,
            )
            for a in body.activities
        ],
    )
    await trip.save()
    return _trip_to_response(trip)


@app.get("/trips")
async def list_trips() -> list[TripResponse]:
    trips = await Trip.objects().all()
    return [_trip_to_response(t) for t in trips]


@app.get("/trips/{trip_id}")
async def get_trip(trip_id: str) -> TripResponse:
    try:
        trip = await Trip.objects().get(trip_id)
    except Trip.DoesNotExist as exc:
        raise HTTPException(status_code=404, detail="Trip not found") from exc
    return _trip_to_response(trip)


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
async def create_route(body: RouteCreate) -> RouteResponse:
    route_obj = Route(
        name=body.name,
        trip_id=body.trip_id,
        steps=[RouteStepModel(**s.model_dump()) for s in body.steps],
    )
    await route_obj.save()
    return _route_to_response(route_obj)


@app.get("/routes")
async def list_routes() -> list[RouteResponse]:
    routes = await Route.objects().all()
    return [_route_to_response(r) for r in routes]


@app.get("/routes/{route_id}")
async def get_route(route_id: str) -> RouteResponse:
    try:
        route_obj = await Route.objects().get(route_id)
    except Route.DoesNotExist as exc:
        raise HTTPException(status_code=404, detail="Route not found") from exc
    return _route_to_response(route_obj)
