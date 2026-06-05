from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator
from surreal_orm import BaseSurrealModel


class GeoPoint(BaseModel):
    type: Literal["Point"] = "Point"
    coordinates: list[float] = Field(..., min_length=2, max_length=2)
    """[longitude, latitude]"""


class GeoPolygon(BaseModel):
    type: Literal["Polygon"] = "Polygon"
    coordinates: list[list[list[float]]]
    """[[[longitude, latitude], ...]] — first/last point must close the ring"""


class Quest(BaseSurrealModel):
    id: str | None = None

    start_time: datetime
    end_time: datetime

    position: GeoPoint | None = None
    area: GeoPolygon | None = None

    num_completions: int | None = None
    description: str
    xp_val: int = Field(..., ge=0)
    issuer_id: str

    @model_validator(mode="after")
    def require_position_or_area(self) -> Quest:
        if self.position is None and self.area is None:
            raise ValueError("At least one of 'position' or 'area' must be provided")
        return self
