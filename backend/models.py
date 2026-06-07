from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field
from surrealdb.data.types.geometry import GeometryLine, GeometryPoint, GeometryPolygon


class Activity(BaseModel):
    """Activity embedded inside a Trip (not a separate table)."""

    type: str
    duration_minutes: int
    specification: str | None = None


class Trip(BaseModel):
    model_config = ConfigDict(arbitrary_types_allowed=True)

    id: str | None = None
    start_time: datetime
    start_location: GeometryPoint
    end_time: datetime
    end_location: GeometryPoint
    activities: list[Activity] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# Route / RouteStep
# ---------------------------------------------------------------------------

class RouteStepType(StrEnum):
    path = "path"
    area = "area"
    location = "location"

class RouteStep(BaseModel):
    model_config = ConfigDict(arbitrary_types_allowed=True)

    type: RouteStepType
    name: str
    description: str | None = None
    duration: float  # in minutes
    area: GeometryPolygon | None = None
    path: GeometryLine | None = None
    location: GeometryPoint | None = None

class Route(BaseModel):
    model_config = ConfigDict(arbitrary_types_allowed=True)

    id: str | None = None
    name: str
    trip_id: str
    steps: list[RouteStep] = Field(default_factory=list)

