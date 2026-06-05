from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, model_validator
from pydantic.alias_generators import to_camel
from pydantic_settings import BaseSettings, SettingsConfigDict
from surreal_orm import SurrealDBConnectionManager
from surrealdb import AsyncSurreal, SurrealError

from models import GeoPoint, GeoPolygon, Quest


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="SURREALDB_", case_sensitive=False, env_file=".env", extra="ignore"
    )

    url: str = Field(default="ws://localhost:8000")
    namespace: str = Field(default="questmap")
    database: str = Field(default="questmap")
    username: str = Field(default="root")
    password: str = Field(default="root")


def _ws_url_to_http(ws_url: str) -> str:
    if ws_url.startswith("wss://"):
        return "https://" + ws_url[len("wss://"):]
    if ws_url.startswith("ws://"):
        return "http://" + ws_url[len("ws://"):]
    return ws_url


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = Settings()
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
    app.state.db = db

    try:
        yield
    finally:
        await SurrealDBConnectionManager.close_connection()
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
        url=settings.url,
        namespace=settings.namespace,
        database=settings.database,
    )


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
