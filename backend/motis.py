from __future__ import annotations

from datetime import datetime
from typing import Any, Literal, Self, cast

import httpx
from pydantic import BaseModel, ConfigDict, Field

Mode = Literal[
    "WALK",
    "BIKE",
    "RENTAL",
    "CAR",
    "CAR_PARKING",
    "CAR_DROPOFF",
    "ODM",
    "RIDE_SHARING",
    "FLEX",
    "DEBUG_BUS_ROUTE",
    "DEBUG_RAILWAY_ROUTE",
    "DEBUG_FERRY_ROUTE",
    "TRANSIT",
    "TRAM",
    "SUBWAY",
    "FERRY",
    "AIRPLANE",
    "BUS",
    "COACH",
    "RAIL",
    "HIGHSPEED_RAIL",
    "LONG_DISTANCE",
    "NIGHT_RAIL",
    "REGIONAL_FAST_RAIL",
    "REGIONAL_RAIL",
    "SUBURBAN",
    "FUNICULAR",
    "AERIAL_LIFT",
    "OTHER",
    "AREAL_LIFT",
    "METRO",
    "CABLE_CAR",
]

PedestrianProfile = Literal["FOOT", "WHEELCHAIR"]
ElevationCosts = Literal["NONE", "LOW", "HIGH"]
Algorithm = Literal["RAPTOR", "PONG", "TB"]


class MotisPlanRequest(BaseModel):
    model_config = ConfigDict(extra="allow", populate_by_name=True)

    from_place: str = Field(..., alias="fromPlace")
    to_place: str = Field(..., alias="toPlace")
    radius: float | None = None
    via: list[str] | None = None
    via_minimum_stay: list[int] | None = Field(default=None, alias="viaMinimumStay")
    time: datetime | None = None
    max_transfers: int | None = Field(default=None, alias="maxTransfers")
    max_travel_time: int | None = Field(default=None, alias="maxTravelTime")
    min_transfer_time: int | None = Field(default=None, alias="minTransferTime")
    additional_transfer_time: int | None = Field(
        default=None, alias="additionalTransferTime"
    )
    transfer_time_factor: float | None = Field(default=None, alias="transferTimeFactor")
    max_matching_distance: float | None = Field(
        default=None, alias="maxMatchingDistance"
    )
    pedestrian_profile: PedestrianProfile | None = Field(
        default=None, alias="pedestrianProfile"
    )
    pedestrian_speed: float | None = Field(default=None, alias="pedestrianSpeed")
    cycling_speed: float | None = Field(default=None, alias="cyclingSpeed")
    elevation_costs: ElevationCosts | None = Field(default=None, alias="elevationCosts")
    use_routed_transfers: bool | None = Field(default=None, alias="useRoutedTransfers")
    detailed_transfers: bool | None = Field(default=None, alias="detailedTransfers")
    detailed_legs: bool | None = Field(default=None, alias="detailedLegs")
    join_interlined_legs: bool | None = Field(default=None, alias="joinInterlinedLegs")
    transit_modes: list[Mode] | None = Field(default=None, alias="transitModes")
    direct_modes: list[Mode] | None = Field(default=None, alias="directModes")
    pre_transit_modes: list[Mode] | None = Field(default=None, alias="preTransitModes")
    post_transit_modes: list[Mode] | None = Field(
        default=None, alias="postTransitModes"
    )
    num_itineraries: int | None = Field(default=None, alias="numItineraries")
    max_itineraries: int | None = Field(default=None, alias="maxItineraries")
    page_cursor: str | None = Field(default=None, alias="pageCursor")
    timetable_view: bool | None = Field(default=None, alias="timetableView")
    arrive_by: bool | None = Field(default=None, alias="arriveBy")
    search_window: int | None = Field(default=None, alias="searchWindow")
    require_bike_transport: bool | None = Field(
        default=None, alias="requireBikeTransport"
    )
    require_car_transport: bool | None = Field(
        default=None, alias="requireCarTransport"
    )
    max_pre_transit_time: int | None = Field(default=None, alias="maxPreTransitTime")
    max_post_transit_time: int | None = Field(default=None, alias="maxPostTransitTime")
    max_direct_time: int | None = Field(default=None, alias="maxDirectTime")
    fastest_direct_factor: float | None = Field(
        default=None, alias="fastestDirectFactor"
    )
    timeout: int | None = None
    passengers: int | None = None
    luggage: int | None = None
    slow_direct: bool | None = Field(default=None, alias="slowDirect")
    fastest_slow_direct_factor: float | None = Field(
        default=None, alias="fastestSlowDirectFactor"
    )
    with_fares: bool | None = Field(default=None, alias="withFares")
    num_leg_alternatives: int | None = Field(default=None, alias="numLegAlternatives")
    with_scheduled_skipped_stops: bool | None = Field(
        default=None, alias="withScheduledSkippedStops"
    )
    language: list[str] | None = None
    algorithm: Algorithm | None = None

    def to_query_params(self) -> dict[str, str]:
        values = self.model_dump(
            by_alias=True,
            exclude_none=True,
            mode="json",
        )
        return {key: self._query_value(value) for key, value in values.items()}

    @staticmethod
    def _query_value(value: Any) -> str:
        if isinstance(value, list):
            return ",".join(str(item) for item in value)
        if isinstance(value, bool):
            return "true" if value else "false"
        return str(value)


class MotisClient:
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

    async def health(self) -> dict[str, Any]:
        response = await self._http_client.get(self._path("/api/v1/health"))
        response.raise_for_status()
        return cast("dict[str, Any]", response.json())

    async def plan(self, plan_request: MotisPlanRequest) -> dict[str, Any]:
        response = await self._http_client.get(
            self._path("/api/v6/plan"),
            params=plan_request.to_query_params(),
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
