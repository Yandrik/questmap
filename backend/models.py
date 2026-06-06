from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from schemas import AreaStep, GeometryPointField, LocationStep, PathStep, RouteStep


class Activity(BaseModel):
    """Activity embedded inside a Trip (not a separate table)."""

    type: str
    duration_minutes: int
    specification: str | None = None


class Trip(BaseModel):
    model_config = ConfigDict(arbitrary_types_allowed=True)

    id: str | None = None
    start_time: datetime
    start_location: GeometryPointField
    end_time: datetime
    end_location: GeometryPointField
    activities: list[Activity] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# Stubs — not yet implemented
# ---------------------------------------------------------------------------


class Quest(BaseModel):
    id: str | None = None


class QuestCompletion(BaseModel):
    id: str | None = None


# ---------------------------------------------------------------------------
# Route / RouteStep
# ---------------------------------------------------------------------------

# Re-export from schemas for convenience
__all__ = ["AreaStep", "LocationStep", "PathStep", "RouteStep"]


class Route(BaseModel):
    id: str | None = None
    name: str
    trip_id: str
    steps: list[RouteStep] = Field(default_factory=list)
