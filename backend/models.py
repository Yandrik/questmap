from surrealdb import Geometry
from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, Field
from surreal_orm import BaseSurrealModel, SurrealConfigDict
from surreal_orm.types import SchemaMode
from surrealdb.data.types.geometry import GeometryPoint, GeometryPolygon,GeometryLine


class Activity(BaseModel):
    """Activity embedded inside a Trip (not a separate table)."""

    type: str
    duration_minutes: int
    specification: str | None = None


class Trip(BaseSurrealModel):
    model_config = SurrealConfigDict(
        table_name="trip",
        schema_mode=SchemaMode.SCHEMAFULL,
        arbitrary_types_allowed=True,
    )

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

class RouteStep(BaseSurrealModel):
    type: RouteStepType
    name: str
    description: str | None = None
    duration: float # in minutes
    area: GeometryPolygon | None = None
    path: GeometryLine | None = None
    location: GeometryPoint | None = None

class Route(BaseSurrealModel):
    model_config = SurrealConfigDict(
        table_name="route",
        schema_mode=SchemaMode.SCHEMAFULL,
        arbitrary_types_allowed=True,
    )

    id: str | None = None
    name: str
    trip_id: str
    steps: list[RouteStep] = Field(default_factory=list)

