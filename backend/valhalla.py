from __future__ import annotations

from typing import Any, Literal, Self, cast

import httpx
from pydantic import BaseModel, ConfigDict, Field, field_validator

CostingType = Literal[
    "auto",
    "bicycle",
    "pedestrian",
    "truck",
    "bus",
    "taxi",
    "motor_scooter",
    "motorcycle",
    "multimodal",
    "bikeshare",
    "auto_pedestrian",
]

ShapeFormat = Literal["polyline6", "polyline5", "geojson", "no_shape"]
Unit = Literal["kilometers", "miles"]


class ValhallaLocation(BaseModel):
    model_config = ConfigDict(extra="allow")

    lat: float = Field(..., ge=-90, le=90)
    lon: float = Field(..., ge=-180, le=180)
    type: Literal["break", "through", "via", "break_through"] = "break"
    name: str | None = None


class ValhallaRouteRequest(BaseModel):
    model_config = ConfigDict(extra="allow")

    locations: list[ValhallaLocation] = Field(..., min_length=2)
    costing: CostingType = "pedestrian"
    costing_options: dict[str, Any] | None = None
    directions_options: dict[str, Any] | None = None
    shape_format: ShapeFormat = "polyline6"
    units: Unit = "kilometers"
    language: str | None = None

    @field_validator("locations")
    @classmethod
    def require_at_least_two_locations(
        cls, locations: list[ValhallaLocation]
    ) -> list[ValhallaLocation]:
        if len(locations) < 2:
            raise ValueError("Valhalla routes require at least two locations")
        return locations


class ValhallaClient:
    def __init__(
        self, base_url: str, http_client: httpx.AsyncClient | None = None
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self._owns_http_client = http_client is None
        self._http_client = http_client or httpx.AsyncClient(
            base_url=self.base_url,
            timeout=httpx.Timeout(30.0, connect=5.0),
        )

    async def close(self) -> None:
        if self._owns_http_client:
            await self._http_client.aclose()

    async def status(self) -> dict[str, Any]:
        response = await self._http_client.get(self._path("/status"))
        response.raise_for_status()
        return cast("dict[str, Any]", response.json())

    async def route(self, route_request: ValhallaRouteRequest) -> dict[str, Any]:
        response = await self._http_client.post(
            self._path("/route"),
            json=route_request.model_dump(exclude_none=True),
        )
        response.raise_for_status()
        return cast("dict[str, Any]", response.json())

    def _path(self, path: str) -> str:
        if self._http_client.base_url:
            return path
        return f"{self.base_url}{path}"

    async def __aenter__(self) -> Self:
        return self

    async def __aexit__(self, *exc_info: object) -> None:
        await self.close()
