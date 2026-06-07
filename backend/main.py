from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, ConfigDict, Field, model_validator
from pydantic.alias_generators import to_camel
from pydantic_settings import BaseSettings, SettingsConfigDict
from surreal_orm import SurrealDBConnectionManager
from surrealdb import AsyncSurreal, SurrealError

from models import GeoPoint, GeoPolygon, Quest, QuestCompletion
from motis import MotisClient, MotisPlanRequest
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

    url: str = Field(default="http://localhost:8010")


def _ws_url_to_http(ws_url: str) -> str:
    if ws_url.startswith("wss://"):
        return "https://" + ws_url[len("wss://") :]
    if ws_url.startswith("ws://"):
        return "http://" + ws_url[len("ws://") :]
    return ws_url


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

    SurrealDBConnectionManager.set_connection(
        url=_ws_url_to_http(settings.url),
        user=settings.username,
        password=settings.password,
        namespace=settings.namespace,
        database=settings.database,
    )

    app.state.settings = settings
    app.state.valhalla_settings = valhalla_settings
    app.state.motis_settings = motis_settings
    app.state.db = db
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
        await SurrealDBConnectionManager.close_connection()
        await db.close()


app = FastAPI(title="Questmap API", lifespan=lifespan)


class HealthResponse(BaseModel):
    status: str


class DatabaseHealthResponse(HealthResponse):
    url: str
    namespace: str
    database: str


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
# Trip-planning endpoints
# ---------------------------------------------------------------------------


@app.post("/trip-planning/sessions")
async def create_trip_planning_session(
    body: TripPlanningRequest, request: Request
) -> TripPlanningStartResponse:
    session_id = await request.app.state.trip_planning.start_session(body)
    return TripPlanningStartResponse(session_id=session_id)


@app.get("/trip-planning/sessions/{session_id}")
async def get_trip_planning_session(
    session_id: str, request: Request
) -> TripPlanningSessionSnapshot:
    try:
        return await request.app.state.trip_planning.get_session(session_id)
    except SessionNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Session not found") from exc


@app.get("/trip-planning/sessions/{session_id}/events")
async def stream_trip_planning_events(
    session_id: str, request: Request
) -> StreamingResponse:
    try:
        await request.app.state.trip_planning.get_session(session_id)
        stream = request.app.state.trip_planning.stream_events(session_id)
        return StreamingResponse(stream, media_type="text/event-stream")
    except SessionNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Session not found") from exc


@app.post("/trip-planning/sessions/{session_id}/answers", status_code=204)
async def answer_trip_planning_question(
    session_id: str,
    body: TripPlanningAnswer,
    request: Request,
) -> None:
    try:
        await request.app.state.trip_planning.answer_question(session_id, body)
    except SessionNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Session not found") from exc
    except StaleAnswerError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except InvalidAnswerError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@app.post("/trip-planning/sessions/{session_id}/cancel", status_code=204)
async def cancel_trip_planning_session(session_id: str, request: Request) -> None:
    try:
        await request.app.state.trip_planning.cancel_session(session_id)
    except SessionNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Session not found") from exc


# ---------------------------------------------------------------------------
# Quest schemas
# ---------------------------------------------------------------------------

_quest_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


class QuestCreate(BaseModel):
    model_config = _quest_config

    start_time: datetime
    end_time: datetime
    position: GeoPoint | None = None
    area: GeoPolygon | None = None
    num_completions: int | None = None
    description: str
    xp_val: int = Field(..., ge=0)
    issuer_id: str = Field(..., alias="issuerID")

    @model_validator(mode="after")
    def require_position_or_area(self) -> "QuestCreate":
        if self.position is None and self.area is None:
            raise ValueError("At least one of 'position' or 'area' must be provided")
        return self


class QuestUpdate(BaseModel):
    model_config = _quest_config

    start_time: datetime | None = None
    end_time: datetime | None = None
    position: GeoPoint | None = None
    area: GeoPolygon | None = None
    num_completions: int | None = None
    description: str | None = None
    xp_val: int | None = Field(default=None, ge=0)
    issuer_id: str | None = Field(default=None, alias="issuerID")


class QuestResponse(BaseModel):
    model_config = _quest_config

    id: str
    start_time: datetime
    end_time: datetime
    position: GeoPoint | None = None
    area: GeoPolygon | None = None
    num_completions: int | None = None
    description: str
    xp_val: int
    issuer_id: str = Field(..., alias="issuerID")


# ---------------------------------------------------------------------------
# Completion schemas
# ---------------------------------------------------------------------------

_completion_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


class CompletionCreate(BaseModel):
    model_config = _completion_config

    quest_id: str = Field(..., alias="questID")
    completion_time: datetime
    completion_user_id: str = Field(..., alias="completionUserID")
    proof_urls: list[str] | None = None
    confirmed: bool
    location: GeoPoint
    user_location: GeoPoint | None = None


class CompletionConfirm(BaseModel):
    confirmed: bool


class CompletionResponse(BaseModel):
    model_config = _completion_config

    id: str
    quest_id: str = Field(..., alias="questID")
    completion_time: datetime
    completion_user_id: str = Field(..., alias="completionUserID")
    proof_urls: list[str] | None = None
    confirmed: bool
    location: GeoPoint
    user_location: GeoPoint | None = None


def _completion_to_response(c: QuestCompletion) -> CompletionResponse:
    return CompletionResponse.model_validate(
        {
            "id": c.id,
            "questID": c.quest_id,
            "completionTime": c.completion_time,
            "completionUserID": c.completion_user_id,
            "proofUrls": c.proof_urls,
            "confirmed": c.confirmed,
            "location": c.location,
            "userLocation": c.user_location,
        }
    )


async def _get_completion_or_404(completion_id: str) -> QuestCompletion:
    try:
        return await QuestCompletion.objects().get(completion_id)
    except QuestCompletion.DoesNotExist as exc:
        raise HTTPException(status_code=404, detail="Completion not found") from exc


def _quest_to_response(q: Quest) -> QuestResponse:
    return QuestResponse.model_validate(
        {
            "id": q.id,
            "start_time": q.start_time,
            "end_time": q.end_time,
            "position": q.position,
            "area": q.area,
            "num_completions": q.num_completions,
            "description": q.description,
            "xp_val": q.xp_val,
            "issuerID": q.issuer_id,
        }
    )


async def _get_quest_or_404(quest_id: str) -> Quest:
    try:
        return await Quest.objects().get(quest_id)
    except Quest.DoesNotExist as exc:
        raise HTTPException(status_code=404, detail="Quest not found") from exc


# ---------------------------------------------------------------------------
# Quest endpoints
# ---------------------------------------------------------------------------


@app.post("/quests", status_code=201)
async def create_quest(body: QuestCreate) -> QuestResponse:
    quest = Quest(
        start_time=body.start_time,
        end_time=body.end_time,
        position=body.position,
        area=body.area,
        num_completions=body.num_completions,
        description=body.description,
        xp_val=body.xp_val,
        issuer_id=body.issuer_id,
    )
    await quest.save()
    return _quest_to_response(quest)


@app.get("/quests")
async def list_quests() -> list[QuestResponse]:
    quests: list[Quest] = await Quest.objects().all()
    return [_quest_to_response(q) for q in quests]


@app.get("/quests/{quest_id}")
async def get_quest(quest_id: str) -> QuestResponse:
    quest = await _get_quest_or_404(quest_id)
    return _quest_to_response(quest)


@app.put("/quests/{quest_id}")
async def update_quest(quest_id: str, body: QuestUpdate) -> QuestResponse:
    quest = await _get_quest_or_404(quest_id)
    updates: dict[str, Any] = {
        k: v
        for k, v in body.model_dump(exclude_unset=True, by_alias=False).items()
        if v is not None
    }
    if updates:
        await quest.merge(**updates)
        await quest.refresh()
    return _quest_to_response(quest)


@app.delete("/quests/{quest_id}", status_code=204)
async def delete_quest(quest_id: str) -> None:
    quest = await _get_quest_or_404(quest_id)
    await quest.delete()


# ---------------------------------------------------------------------------
# Completion endpoints
# ---------------------------------------------------------------------------


@app.post("/completions", status_code=201)
async def create_completion(body: CompletionCreate) -> CompletionResponse:
    completion = QuestCompletion(
        quest_id=body.quest_id,
        completion_time=body.completion_time,
        completion_user_id=body.completion_user_id,
        proof_urls=body.proof_urls,
        confirmed=body.confirmed,
        location=body.location,
        user_location=body.user_location,
    )
    await completion.save()
    return _completion_to_response(completion)


@app.get("/quests/{quest_id}/completions")
async def list_quest_completions(quest_id: str) -> list[CompletionResponse]:
    completions: list[QuestCompletion] = (
        await QuestCompletion.objects().filter(quest_id=quest_id).all()
    )
    return [_completion_to_response(c) for c in completions]


@app.put("/completions/{completion_id}/confirm")
async def confirm_completion(
    completion_id: str, body: CompletionConfirm
) -> CompletionResponse:
    completion = await _get_completion_or_404(completion_id)
    await completion.merge(confirmed=body.confirmed)
    await completion.refresh()
    return _completion_to_response(completion)
