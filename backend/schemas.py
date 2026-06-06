from datetime import datetime
from enum import StrEnum
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field
from pydantic.functional_serializers import PlainSerializer
from pydantic.functional_validators import BeforeValidator
from surrealdb.data.types.geometry import GeometryLine, GeometryPoint, GeometryPolygon

from models import RouteStepType

# ---------------------------------------------------------------------------
# Annotated geometry field types (API <-> surrealdb native types)
# ---------------------------------------------------------------------------


def _parse_point(v) -> GeometryPoint:
    if isinstance(v, GeometryPoint):
        return v
    if isinstance(v, dict) and v.get("type") == "Point":
        lon, lat = v["coordinates"]
        return GeometryPoint(lon, lat)
    raise ValueError(f"Cannot parse GeometryPoint from {v!r}")


def _serialize_point(v: GeometryPoint) -> dict:
    return {"type": "Point", "coordinates": [v.longitude, v.latitude]}


def _parse_line(v) -> GeometryLine:
    if isinstance(v, GeometryLine):
        return v
    if isinstance(v, dict) and v.get("type") == "LineString":
        return GeometryLine(
            *[GeometryPoint(c[0], c[1]) for c in v["coordinates"]]
        )
    raise ValueError(f"Cannot parse GeometryLine from {v!r}")


def _serialize_line(v: GeometryLine) -> dict:
    return {
        "type": "LineString",
        "coordinates": [[p.longitude, p.latitude] for p in v.geometry_points],
    }


def _parse_polygon(v) -> GeometryPolygon:
    if isinstance(v, GeometryPolygon):
        return v
    if isinstance(v, dict) and v.get("type") == "Polygon":
        return GeometryPolygon(
            *[
                GeometryLine(*[GeometryPoint(c[0], c[1]) for c in ring])
                for ring in v["coordinates"]
            ]
        )
    raise ValueError(f"Cannot parse GeometryPolygon from {v!r}")


def _serialize_polygon(v: GeometryPolygon) -> dict:
    return {
        "type": "Polygon",
        "coordinates": [
            [[p.longitude, p.latitude] for p in ring.geometry_points]
            for ring in v.geometry_lines
        ],
    }


GeometryPointField = Annotated[
    GeometryPoint,
    BeforeValidator(_parse_point),
    PlainSerializer(_serialize_point, return_type=dict, when_used="json"),
]

GeometryLineField = Annotated[
    GeometryLine,
    BeforeValidator(_parse_line),
    PlainSerializer(_serialize_line, return_type=dict, when_used="json"),
]

GeometryPolygonField = Annotated[
    GeometryPolygon,
    BeforeValidator(_parse_polygon),
    PlainSerializer(_serialize_polygon, return_type=dict, when_used="json"),
]



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
    model_config = ConfigDict(arbitrary_types_allowed=True)

    start_time: datetime
    start_location: GeometryPointField
    end_time: datetime
    end_location: GeometryPointField
    activities: list[ActivityCreate] = []


class TripResponse(BaseModel):
    model_config = ConfigDict(arbitrary_types_allowed=True)

    id: str
    start_time: datetime
    start_location: GeometryPointField
    end_time: datetime
    end_location: GeometryPointField
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


# ---------------------------------------------------------------------------
# Route / RouteStep -- discriminated union of typed step classes
# ---------------------------------------------------------------------------

_STEP_CONFIG = ConfigDict(arbitrary_types_allowed=True)


class LocationStep(BaseModel):
    model_config = _STEP_CONFIG

    type: Literal[RouteStepType.location] = RouteStepType.location
    name: str
    duration: float  # seconds
    description: str | None = None
    location: GeometryPointField


class PathStep(BaseModel):
    model_config = _STEP_CONFIG

    type: Literal[RouteStepType.path] = RouteStepType.path
    name: str
    duration: float  # seconds
    description: str | None = None
    path: GeometryLineField


class AreaStep(BaseModel):
    model_config = _STEP_CONFIG

    type: Literal[RouteStepType.area] = RouteStepType.area
    name: str
    duration: float  # seconds
    description: str | None = None
    area: GeometryPolygonField


RouteStep = Annotated[
    LocationStep | PathStep | AreaStep,
    Field(discriminator="type"),
]


class RouteCreate(BaseModel):
    name: str
    trip_id: str
    steps: list[RouteStep] = []


class RouteResponse(BaseModel):
    id: str
    name: str
    trip_id: str
    steps: list[RouteStep] = []


class CompletionConfirm(BaseModel):
    pass
