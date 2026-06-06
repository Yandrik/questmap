from datetime import datetime

from pydantic import BaseModel


class GeoPoint(BaseModel):
    lat: float
    lon: float


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------


class HealthResponse(BaseModel):
    status: str


class DatabaseHealthResponse(BaseModel):
    status: str
    url: str
    namespace: str
    database: str


# ---------------------------------------------------------------------------
# Activity (embedded in Trip)
# ---------------------------------------------------------------------------


class ActivityCreate(BaseModel):
    type: str
    duration_minutes: int
    specification: str | None = None


class ActivityResponse(BaseModel):
    type: str
    duration_minutes: int
    specification: str | None = None


# ---------------------------------------------------------------------------
# Trip
# ---------------------------------------------------------------------------


class TripCreate(BaseModel):
    start_time: datetime
    start_location: GeoPoint
    end_time: datetime
    end_location: GeoPoint
    activities: list[ActivityCreate] = []


class TripResponse(BaseModel):
    id: str
    start_time: datetime
    start_location: GeoPoint
    end_time: datetime
    end_location: GeoPoint
    activities: list[ActivityResponse] = []


# ---------------------------------------------------------------------------
# Quest (stubs — not yet implemented)
# ---------------------------------------------------------------------------


class QuestCreate(BaseModel):
    pass


class QuestResponse(BaseModel):
    pass


class QuestUpdate(BaseModel):
    pass


# ---------------------------------------------------------------------------
# Completion (stubs — not yet implemented)
# ---------------------------------------------------------------------------


class CompletionCreate(BaseModel):
    pass


class CompletionResponse(BaseModel):
    pass


class CompletionConfirm(BaseModel):
    pass
