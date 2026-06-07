from __future__ import annotations

import base64
import json
from dataclasses import dataclass
from os import getenv
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator
from pydantic_ai import Agent, BinaryContent
from pydantic_ai.models.openai import OpenAIChatModel
from pydantic_ai.providers.openai import OpenAIProvider
from surrealdb import AsyncSurreal


class Address(BaseModel):
    country: str | None = None
    postcode: str | None = None
    city: str | None = None
    street: str | None = None
    housenumber: str | None = None
    suburb: str | None = None


class LocationGeometry(BaseModel):
    type: Literal["Point"]
    coordinates: tuple[float, float]


class LocationProperties(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="allow")

    osm_type: str | None = None
    osm_id: int | None = None
    address: Address | None = None
    faculty: str | None = None
    name: str | None = None
    office: str | None = None
    operator: str | None = None
    toilets_wheelchair: str | None = Field(None, alias="toilets:wheelchair")
    wheelchair: str | None = None
    wikidata: str | None = None
    wikipedia: str | None = None


class TripLocations(BaseModel):
    city: str
    lat: float
    lon: float
    category: Literal["shop", "restaurant", "sightseeing", "transit", "other"]
    notes: str | None = None
    heatmap_image_b64: BinaryContent | None = None
    map_image_b64: str | None = None


class LocationsObject(BaseModel):
    type: Literal["Feature"]
    geometry: LocationGeometry
    properties: LocationProperties

    def to_locations_of_interest(self) -> TripLocations:
        return TripLocations(
            city=(self.properties.address.city if self.properties.address else None)
            or self.properties.name
            or "",
            lat=self.geometry.coordinates[1],
            lon=self.geometry.coordinates[0],
            category="other",
        )


class TripPlanInput(BaseModel):
    start_point: tuple[float, float]
    end_point: tuple[float, float]
    trip_locations: list[TripLocations]
    max_stops: int = 30
    radius_meters: int = 5000

    @field_validator("trip_locations", mode="before")
    @classmethod
    def _normalize_geojson_feature(cls, value: Any) -> Any:
        if isinstance(value, dict) and value.get("type") == "Feature":
            return [LocationsObject.model_validate(value).to_locations_of_interest()]
        return value


class TripPlanOutput(BaseModel):
    summary: str
    ordered_points: list[LocationsObject]
    route_strategy: str
    warnings: list[str] = Field(default_factory=list)


@dataclass(frozen=True)
class Deps:
    db_url: str
    db_ns: str
    db_name: str
    db_user: str
    db_pass: str


async def search_pois(
    city: str,
    lat: float,
    lon: float,
    radius_meters: int,
    category: str | None = None,
) -> str:
    """Search SurrealDB for nearby points of interest around a coordinate."""
    db_url = getenv("SURREALDB_URL", "ws://localhost:8001")
    db_ns = getenv("SURREALDB_NAMESPACE", "main")
    db_name = getenv("SURREALDB_DATABASE", "main")
    db_user = getenv("SURREALDB_USERNAME", "root")
    db_pass = getenv("SURREALDB_PASSWORD", "root")

    async with AsyncSurreal(db_url) as db:
        await db.signin({"username": db_user, "password": db_pass})
        await db.use(db_ns, db_name)
        query, variables = _poi_query(city, lat, lon, radius_meters, category)
        result = await db.query(query, variables)

    serializable_result = _jsonable(result)
    filtered_result = [
        {
            "id": item.get("id"),
            "name": item.get("name"),
            "lat": item.get("lat"),
            "lon": item.get("lon"),
            "family": item.get("primary_family"),
            "category": item.get("primary_type")
            or (item.get("tags") or {}).get("category"),
        }
        for item in serializable_result
        if isinstance(item, dict)
    ]
    return json.dumps(filtered_result, ensure_ascii=False)


async def prompt_user(message: str) -> str:
    """Non-blocking placeholder for agent clarification prompts."""
    return f"Question deferred to API workflow: {message}"


async def plan_trip(inp: TripPlanInput) -> TripPlanOutput:
    agent = _build_agent()
    prompt = _planning_prompt(inp)
    result = await agent.run(
        prompt,
        deps=Deps(
            db_url=getenv("SURREALDB_URL", "ws://localhost:8001"),
            db_ns=getenv("SURREALDB_NAMESPACE", "questmap"),
            db_name=getenv("SURREALDB_DATABASE", "questmap"),
            db_user=getenv("SURREALDB_USERNAME", "root"),
            db_pass=getenv("SURREALDB_PASSWORD", "root"),
        ),
        model_settings={"temperature": 0.2},
    )
    return TripPlanOutput.model_validate(result.output)


def _build_agent() -> Agent[Any, Any]:
    base_url = getenv("BACKENDPOINT_URL")
    if not base_url:
        raise RuntimeError("BACKENDPOINT_URL must be set to run the local agent.")
    model_name = getenv("PLANNING_AGENT_MODEL", "Qwen3.6-27B-MTP-GGUF")
    model = OpenAIChatModel(
        model_name=model_name,
        provider=OpenAIProvider(base_url=base_url),
    )
    agent: Agent[Any, Any] = Agent(
        model=model,
        output_type=TripPlanOutput,
        system_prompt="You're a helpful local trip-planning assistant.",
    )
    agent.tool_plain(search_pois)
    agent.tool_plain(prompt_user)
    return agent


def _planning_prompt(inp: TripPlanInput) -> str:
    prompt = f"""
Plan a city trip route using the heatmap image and map context.

Start: {inp.start_point}
End: {inp.end_point}
Trip Locations: {inp.trip_locations}
Max stops: {inp.max_stops}
Radius: {inp.radius_meters} meters

For each trip location, use search_pois once to find nearby candidate POIs.
Choose one point per requested location when possible. Prefer points that match
the requested category and make a reasonable route from start to end. Return
only structured output in the required schema.
"""
    first_location = next(iter(inp.trip_locations), None)
    if first_location and first_location.heatmap_image_b64:
        prompt += "\n\nHeatmap image (data URL): "
        prompt += f"data:image/png,{first_location.heatmap_image_b64}"
    return prompt


def _poi_query(
    city: str,
    lat: float,
    lon: float,
    radius_meters: int,
    category: str | None,
) -> tuple[str, dict[str, Any]]:
    category_clause = (
        """
        AND (primary_type = $category OR tags.category = $category)
        """
        if category
        else ""
    )
    query = f"""
    SELECT id, osm_type, osm_id, name, operator, lat, lon,
      location, primary_family, primary_type, address, access,
      wheelchair, fee, tags,
      geo::distance(location, <point>[<float>$lon, <float>$lat]) AS distance_m
    FROM osm_object
    WHERE address.city = $city
      AND location != NONE
      {category_clause}
      AND geo::distance(
        location,
        <point>[<float>$lon, <float>$lat]
      ) < <float>$radius
    ORDER BY distance_m ASC
    LIMIT 20;
    """
    return (
        query,
        {
            "city": city,
            "category": category,
            "lat": lat,
            "lon": lon,
            "radius": radius_meters,
        },
    )


def _jsonable(value: Any) -> Any:
    if value is None or isinstance(value, str | int | float | bool):
        return value
    if isinstance(value, bytes):
        return base64.b64encode(value).decode("ascii")
    if isinstance(value, dict):
        return {key: _jsonable(item) for key, item in value.items()}
    if isinstance(value, list | tuple | set):
        return [_jsonable(item) for item in value]
    return str(value)


if __name__ == "__main__":
    import asyncio

    sample_input = TripPlanInput(
        start_point=(48.398678, 9.983708),
        end_point=(48.398678, 9.983708),
        trip_locations=[
            TripLocations(
                city="Ulm",
                lat=48.400833,
                lon=9.987222,
                category="restaurant",
                notes="Pizzeria",
            )
        ],
        max_stops=5,
        radius_meters=4000,
    )

    print(asyncio.run(plan_trip(sample_input)))
