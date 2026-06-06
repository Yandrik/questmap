from datetime import datetime

from pydantic import BaseModel, Field

from schemas import GeoPoint


class Activity(BaseModel):
    """Activity embedded inside a Trip (not a separate table)."""

    type: str
    duration_minutes: int
    specification: str | None = None


class Trip(BaseModel):
    id: str | None = None
    start_time: datetime
    start_location: GeoPoint
    end_time: datetime
    end_location: GeoPoint
    activities: list[Activity] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# Stubs — not yet implemented
# ---------------------------------------------------------------------------


class Quest(BaseModel):
    id: str | None = None


class QuestCompletion(BaseModel):
    id: str | None = None
