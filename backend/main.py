import logging
import sys
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from os import getenv
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from surrealdb import AsyncSurreal, RecordID

from db import dict_to_route, dict_to_trip, init_db
from models import Route, Trip
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
from trip_planning import (
    InvalidAnswerError,
    SessionNotFoundError,
    StaleAnswerError,
    SurrealTripPlanningRepository,
    TripPlanningService,
)
from trip_planning_models import (
    TripPlanningAnswer,
    TripPlanningRequest,
    TripPlanningSessionSnapshot,
    TripPlanningStartResponse,
)
from valhalla import ValhallaClient, ValhallaRouteRequest


def _configure_logging() -> None:
    level_name = getenv("LOG_LEVEL", "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)
    root_logger = logging.getLogger()
    if not root_logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(
            logging.Formatter(
                "%(levelname)s:%(name)s:%(message)s",
            )
        )
        root_logger.addHandler(handler)
    root_logger.setLevel(level)
    for logger_name in (
        "main",
        "trip_planning",
        "pydantic_ai_local",
        "uvicorn",
        "uvicorn.error",
        "uvicorn.access",
    ):
        logging.getLogger(logger_name).setLevel(level)
    for logger_name in (
        "httpcore",
        "httpx",
        "websockets",
        "websockets.client",
    ):
        logging.getLogger(logger_name).setLevel(logging.WARNING)


_configure_logging()
logger = logging.getLogger(__name__)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="SURREALDB_", case_sensitive=False, env_file=".env", extra="ignore"
    )

    url: str = Field(default="ws://localhost:8001")
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

    async with AsyncSurreal(settings.url) as db:
        await db.signin({"username": settings.username, "password": settings.password})
        await db.use(settings.namespace, settings.database)
        await init_db(db)
        app.state.db = db
        app.state.settings = settings
        app.state.valhalla_settings = valhalla_settings
        app.state.motis_settings = motis_settings
        app.state.valhalla = ValhallaClient(valhalla_settings.url)
        app.state.motis = MotisClient(motis_settings.url)
        app.state.trip_planning = TripPlanningService(
            SurrealTripPlanningRepository(db),
            app.state.valhalla,
            app.state.motis,
        )

        try:
            yield
        finally:
            await app.state.trip_planning.close()
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
    plan_request = _normalize_transit_plan_time(body)
    logger.info(
        "Transit plan request from=%s to=%s received_time=%s used_time=%s",
        body.from_place,
        body.to_place,
        body.time.isoformat() if body.time is not None else None,
        "motis-default-now" if plan_request.time is None else plan_request.time,
    )
    try:
        return await request.app.state.motis.plan(plan_request)
    except httpx.HTTPStatusError as exc:
        status_code = exc.response.status_code
        logger.warning(
            "Transit plan failed status=%s from=%s to=%s used_time=%s detail=%s",
            status_code,
            plan_request.from_place,
            plan_request.to_place,
            "motis-default-now" if plan_request.time is None else plan_request.time,
            exc.response.text,
        )
        if status_code in {400, 404, 422, 429}:
            raise HTTPException(
                status_code=status_code, detail=exc.response.text
            ) from exc
        raise HTTPException(status_code=502, detail="MOTIS plan failed") from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail="MOTIS plan failed") from exc


def _normalize_transit_plan_time(body: MotisPlanRequest) -> MotisPlanRequest:
    return body.model_copy(update={"time": None})


# ---------------------------------------------------------------------------
# Trip-planning endpoints
# ---------------------------------------------------------------------------


@app.post("/trip-planning/sessions")
async def create_trip_planning_session(
    body: TripPlanningRequest, request: Request
) -> TripPlanningStartResponse:
    logger.info(
        "Create trip-planning session request draft_id=%s planner_mode=%s "
        "steps=%s modes=%s",
        body.draft_id,
        body.planner_mode,
        len(body.steps),
        body.transport_modes,
    )
    session_id = await request.app.state.trip_planning.start_session(body)
    logger.info("Create trip-planning session accepted session_id=%s", session_id)
    return TripPlanningStartResponse(session_id=session_id)


@app.get("/trip-planning/sessions/{session_id}")
async def get_trip_planning_session(
    session_id: str, request: Request
) -> TripPlanningSessionSnapshot:
    try:
        snapshot = await request.app.state.trip_planning.get_session(session_id)
        logger.info(
            "Get trip-planning session session_id=%s state=%s",
            session_id,
            snapshot.state,
        )
        return snapshot
    except SessionNotFoundError as exc:
        logger.warning("Get trip-planning session not found session_id=%s", session_id)
        raise HTTPException(status_code=404, detail="Session not found") from exc


@app.get("/trip-planning/sessions/{session_id}/events")
async def stream_trip_planning_events(
    session_id: str, request: Request
) -> StreamingResponse:
    try:
        await request.app.state.trip_planning.get_session(session_id)
        logger.info("Stream trip-planning events request session_id=%s", session_id)
        stream = request.app.state.trip_planning.stream_events(session_id)
        return StreamingResponse(
            stream,
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "X-Accel-Buffering": "no",
            },
        )
    except SessionNotFoundError as exc:
        logger.warning(
            "Stream trip-planning events not found session_id=%s", session_id
        )
        raise HTTPException(status_code=404, detail="Session not found") from exc


@app.post("/trip-planning/sessions/{session_id}/answers", status_code=204)
async def answer_trip_planning_question(
    session_id: str,
    body: TripPlanningAnswer,
    request: Request,
) -> None:
    try:
        logger.info(
            "Answer trip-planning question request session_id=%s question_id=%s",
            session_id,
            body.question_id,
        )
        await request.app.state.trip_planning.answer_question(session_id, body)
    except SessionNotFoundError as exc:
        logger.warning(
            "Answer trip-planning question session not found session_id=%s",
            session_id,
        )
        raise HTTPException(status_code=404, detail="Session not found") from exc
    except StaleAnswerError as exc:
        logger.warning(
            "Answer trip-planning question stale session_id=%s question_id=%s error=%s",
            session_id,
            body.question_id,
            exc,
        )
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except InvalidAnswerError as exc:
        logger.warning(
            "Answer trip-planning question invalid session_id=%s "
            "question_id=%s error=%s",
            session_id,
            body.question_id,
            exc,
        )
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@app.post("/trip-planning/sessions/{session_id}/cancel", status_code=204)
async def cancel_trip_planning_session(session_id: str, request: Request) -> None:
    try:
        logger.info("Cancel trip-planning session request session_id=%s", session_id)
        await request.app.state.trip_planning.cancel_session(session_id)
    except SessionNotFoundError as exc:
        logger.warning(
            "Cancel trip-planning session not found session_id=%s", session_id
        )
        raise HTTPException(status_code=404, detail="Session not found") from exc


# ---------------------------------------------------------------------------
# Quest schemas
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
    result = await db.create(
        "trip",
        {
            "start_time": body.start_time,
            "start_location": body.start_location,
            "end_time": body.end_time,
            "end_location": body.end_location,
            "activities": [a.model_dump() for a in body.activities],
        },
    )
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
        steps=[_route_step_to_response(step) for step in route_obj.steps],
    )


def _route_step_to_response(step: Any) -> dict[str, Any]:
    payload = {
        "type": step.type,
        "name": step.name,
        "duration": step.duration,
        "description": step.description,
    }
    if step.location is not None:
        payload["location"] = step.location
    if step.path is not None:
        payload["path"] = step.path
    if step.area is not None:
        payload["area"] = step.area
    return payload


@app.post("/routes", status_code=201)
async def create_route(body: RouteCreate, request: Request) -> RouteResponse:
    db = request.app.state.db
    result = await db.create(
        "route",
        {
            "name": body.name,
            "trip_id": body.trip_id,
            "steps": [s.model_dump(mode="json") for s in body.steps],
        },
    )
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
