from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator
from pydantic.alias_generators import to_camel

_api_config = ConfigDict(
    alias_generator=to_camel,
    populate_by_name=True,
    extra="ignore",
)
_api_config_allow_extra = ConfigDict(
    alias_generator=to_camel,
    populate_by_name=True,
    extra="allow",
)

TransportMode = Literal["walk", "bike", "drive", "publicTransport"]
ItineraryStepType = Literal[
    "shop",
    "eat",
    "party",
    "walk",
    "sightsee",
    "meander",
    "exactLocation",
]
LocationConstraintType = Literal[
    "exactPoint",
    "aroundPoint",
    "areaCircle",
    "wherever",
]
TripPlanItemType = Literal["activity", "travel"]
TripPlanningQuestionKind = Literal[
    "yesNo",
    "number",
    "text",
    "selection",
    "routeChoice",
]
TripPlanningEventType = Literal[
    "status",
    "question",
    "partialPlan",
    "finalPlan",
    "error",
    "done",
]
TripPlanningSessionState = Literal[
    "queued",
    "running",
    "waitingForAnswer",
    "completed",
    "failed",
    "cancelled",
]


class GeoCoordinate(BaseModel):
    model_config = _api_config

    lat: float = Field(..., ge=-90, le=90)
    lon: float = Field(..., ge=-180, le=180)
    label: str | None = None


class TimeConstraint(BaseModel):
    model_config = _api_config_allow_extra

    start_time: datetime | None = None
    arrival_time: datetime | None = None
    duration_minutes: int = Field(..., gt=0)

    @model_validator(mode="after")
    def validate_interval(self) -> TimeConstraint:
        if self.start_time is None or self.arrival_time is None:
            return self
        interval_seconds = (self.arrival_time - self.start_time).total_seconds()
        if interval_seconds < self.duration_minutes * 60:
            raise ValueError("Time interval cannot fit durationMinutes")
        return self


class LocationConstraint(BaseModel):
    model_config = _api_config_allow_extra

    type: LocationConstraintType
    point: GeoCoordinate | None = None
    center: GeoCoordinate | None = None
    radius_meters: float | None = Field(default=None, gt=0)
    max_transport_minutes: int | None = Field(default=None, gt=0)

    @model_validator(mode="after")
    def validate_shape(self) -> LocationConstraint:
        if self.type in {"exactPoint", "aroundPoint"} and self.point is None:
            raise ValueError(f"{self.type} requires point")
        if self.type == "areaCircle" and self.center is None:
            raise ValueError("areaCircle requires center")
        return self


class ItineraryStepDraft(BaseModel):
    model_config = _api_config_allow_extra

    id: str
    type: ItineraryStepType
    title: str
    details: str = ""
    time: TimeConstraint
    location: LocationConstraint
    icon_key: str | None = None
    color_value: int | None = None


class TripRouteSegment(BaseModel):
    model_config = _api_config

    transport_mode: TransportMode
    geometry: list[GeoCoordinate] = Field(default_factory=list)
    description: str | None = None


class TripPlanItem(BaseModel):
    model_config = _api_config

    id: str
    type: TripPlanItemType
    title: str
    description: str
    reasoning: str | None = None
    source_draft_step_id: str | None = None
    step_type: ItineraryStepType | None = None
    transport_mode: TransportMode | None = None
    start_time: datetime | None = None
    end_time: datetime | None = None
    location: GeoCoordinate | None = None
    visual_target: LocationConstraint | None = None
    geometry: list[GeoCoordinate] = Field(default_factory=list)
    segments: list[TripRouteSegment] = Field(default_factory=list)


class TripPlan(BaseModel):
    model_config = _api_config

    id: str
    title: str
    summary: str | None = None
    items: list[TripPlanItem] = Field(default_factory=list)


class TripPlanningRequest(BaseModel):
    model_config = _api_config

    draft_id: str
    start_location: GeoCoordinate
    end_location: GeoCoordinate | None = None
    transport_modes: list[TransportMode] = Field(..., min_length=1)
    steps: list[ItineraryStepDraft] = Field(..., min_length=1)


class TripPlanningStartResponse(BaseModel):
    model_config = _api_config

    session_id: str


class TripQuestionOption(BaseModel):
    model_config = _api_config

    id: str
    title: str
    description: str | None = None
    image_url: str | None = None
    payload: dict[str, Any] | None = None


class TripPlanningQuestion(BaseModel):
    model_config = _api_config

    id: str
    kind: TripPlanningQuestionKind
    prompt: str
    unit: str | None = None
    options: list[TripQuestionOption] = Field(default_factory=list)


class TripPlanningAnswer(BaseModel):
    model_config = _api_config

    question_id: str
    value: Any


class TripPlanningEventPayload(BaseModel):
    model_config = _api_config

    type: TripPlanningEventType
    message: str | None = None
    question: TripPlanningQuestion | None = None
    plan: TripPlan | None = None


class TripPlanningSessionSnapshot(BaseModel):
    model_config = _api_config

    session_id: str
    draft_id: str
    state: TripPlanningSessionState
    request: TripPlanningRequest
    current_question: TripPlanningQuestion | None = None
    latest_partial_plan: TripPlan | None = None
    final_plan: TripPlan | None = None
    last_message: str | None = None
    created_at: datetime
    updated_at: datetime
