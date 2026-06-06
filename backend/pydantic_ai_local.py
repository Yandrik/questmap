from __future__ import annotations

import base64
import json
from dataclasses import dataclass
from typing import Any, Literal
import httpx
from os import getenv

from pydantic import BaseModel, Field, field_validator
from pydantic_ai import Agent, BinaryContent
from pydantic_ai.models.openai import OpenAIModel
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

    class Config:
        allow_population_by_field_name = True
        extra = "allow"


class TripPlanInput(BaseModel):
    start_point: tuple[float, float]
    end_point: tuple[float, float]
    trip_locations: list[TripLocations]
    max_stops: int = 30
    radius_meters: int = 5000

    @field_validator("trip_locations", mode="before")#, each_item=True)
    def _normalize_geojson_feature(cls, value):
        if isinstance(value, dict) and value.get("type") == "Feature":
            return LocationsObject.model_validate(value).to_locations_of_interest()
        return value


class TripLocations(BaseModel):
    city: str
    lat: float
    lon: float
    category: Literal["shop", "restaurant", "sightseeing", "transit", "other"] = "other"
    notes: str | None = None
    heatmap_image_b64: BinaryContent | None = None
    map_image_b64: str | None = None


class TripPlanOutput(BaseModel):
    summary: str
    ordered_points: list[LocationsObject]
    route_strategy: str
    warnings: list[str] = []


class LocationsObject(BaseModel):
    type: Literal["Feature"]
    geometry: LocationGeometry
    properties: LocationProperties

    def to_locations_of_interest(self) -> TripLocations:
        return TripLocations(
            city=self.properties.addr_city or self.properties.name or "",
            lat=self.geometry.coordinates[1],
            lon=self.geometry.coordinates[0],
            category="other",
        )
    


@dataclass
class Deps:
    db_url: str
    db_ns: str
    db_name: str
    db_user: str
    db_pass: str



ollama_model = OpenAIModel(
    model_name='Qwen3.6-27B-MTP-GGUF',  # or 'llama3.2' without the tag
    provider=OpenAIProvider(base_url=getenv("BACKENDPOINT_URL"))
)

# Create the Agent
agent = Agent(
    model=ollama_model,
    system_prompt="You're a helpful assistant running locally."
)


@agent.tool_plain
async def search_pois(city: str, lat: float, lon: float, radius_meters: int, category: str | None = None) -> str:
    """
    Search SurrealDB for nearby points of interest around a geo coordinate.
    Returns JSON string with candidate POIs.
    """
    async with AsyncSurreal("ws://localhost:8001") as db:
        await db.signin({"username": "root", "password": "root"})
        await db.use("main", "main")

        if category:
            query = """
            SELECT id, osm_type, osm_id, name, operator, lat, lon,
                   location, primary_family, primary_type,
                   address, access, wheelchair, fee, tags,
                   geo::distance(location, <point>[<float>$lon, <float>$lat]) AS distance_m
            FROM osm_object
            WHERE address.city = $city
            AND (primary_type = $category
                OR tags.category = $category)
            AND location != NONE
            AND geo::distance(location, <point>[<float>$lon, <float>$lat]) < <float>$radius
            LIMIT 20;
            """
            vars_ = {"city": city, "category": category, "lat": lat, "lon": lon, "radius": radius_meters}

        else:
            query = """
            SELECT id, osm_type, osm_id, name, operator, lat, lon,
                   location, primary_family, primary_type,
                   address, access, wheelchair, fee, tags,
                   geo::distance(location, <point>[<float>$lon, <float>$lat]) AS distance_m
            FROM osm_object
            WHERE address.city = $city
            AND location != NONE
            AND geo::distance(location, <point>[<float>$lon, <float>$lat]) < <float>$radius
            ORDER BY distance_m ASC
            LIMIT 20;
            """
            vars_ = {"city": city, "lat": lat, "lon": lon, "radius": radius_meters}

        result = await db.query(query, vars_)
        #print(f"search_pois raw result: {result}")

        def make_json_serializable(o: Any):
            if o is None or isinstance(o, (str, int, float, bool)):
                return o
            if isinstance(o, bytes):
                return base64.b64encode(o).decode("ascii")
            if isinstance(o, dict):
                return {k: make_json_serializable(v) for k, v in o.items()}
            if isinstance(o, (list, tuple, set)):
                return [make_json_serializable(v) for v in o]
            # Fallback: try to use __dict__ or convert to string
            if hasattr(o, "__dict__"):
                try:
                    return {k: make_json_serializable(v) for k, v in o.__dict__.items()}
                except Exception:
                    pass
            try:
                return str(o)
            except Exception:
                return repr(o)

        serializable_result = make_json_serializable(result)
        filtered_result = [
            {
                "id": item.get("id"),
                "name": item.get("name"),
                "lat": item.get("lat"),
                "lon": item.get("lon"),
                "family": item.get("primary_family"),
                "category": item.get("primary_type") or item.get("tags", {}).get("category"),
            }
            for item in serializable_result
        ]
        #print("search_pois result (filtered):", filtered_result)
        return json.dumps(filtered_result, ensure_ascii=False)

@agent.tool_plain
async def prompt_user(message: str) -> str:
    """
    Prompt the user for input during the planning process.
    The agent can use this to ask clarifying questions or get preferences.
    """
    print(f"Agent asks: {message}")
    user_input = input("Your answer: ")
    return user_input

async def plan_trip(inp: TripPlanInput) -> TripPlanOutput:
    prompt = f"""
Plan a city trip route using the heatmap image and map context.

Start: {inp.start_point}
End: {inp.end_point}
Trip Locations: {inp.trip_locations}
Max stops: {inp.max_stops}
Radius: {inp.radius_meters} meters

Instructions:
For each Trip Location:
    - Interpret the heatmap to identify dense commercial or interesting areas.
    - Use the map image context if provided.
    - Use the search_pois tool only ONCE per Trip Location to find nearby Location Objects, especially in areas highlighted by the heatmap.
    - You will get a list of candidate POIs to choose from.
    - If the List is empty, or the Objects in the list do not fulfill the criteria, you can skip that Trip Location.
    - Choose ONLY ONE POINT that fit the criteria and that create a reasonable route from start to end, prioritizing those near the heatmap hotspots and matching the categories of interest.
In general:
    - Prefer points that make a reasonable route from start to end.
    - Return only structured output in the required schema.

Output a JSON with the following format:
{{
    "summary": "Brief summary of the planned trip",
    "ordered_points": [
        {{
            "name": "Name of the point of interest",
            "lat": 0.0,
            "lon": 0.0,
            "category": "shop | restaurant | sightseeing | transit | other",
            "reason": "Brief reason why this point was included in the route",
            "confidence": 0.0  # confidence level from 0 to 1
        }},
        ...
    ],
    "route_strategy": "Description of the overall route strategy (e.g., 'prioritized restaurants near heatmap hotspots')",
    "warnings": ["Any warnings about the planned route, e.g., 'the route includes a long walk between point A and B', 'point C might be closed on certain days', etc.]
}}
"""

    # Append the heatmap as a data URL into the prompt to avoid constructing
    # internal Message objects (pydantic_ai expects its own message types).
    if inp.trip_locations and inp.trip_locations[0].heatmap_image_b64:
        prompt += "\n\nHeatmap image (data URL): "
        prompt += f"data:image/png,{inp.trip_locations[0].heatmap_image_b64}"
 
    result = await agent.run(
        prompt,
        deps=Deps(
            db_url="ws://your-surrealdb-host:8000/rpc",
            db_ns="trip_planner",
            db_name="pois",
            db_user="root",
            db_pass="root",
        ),
        model_settings={"temperature": 0.2},
        # message_history omitted to avoid constructing pydantic_ai internal Message objects
    )
    return result.output

image_response = httpx.get('https://iili.io/3Hs4FMg.png')

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
                notes="Pizzaria",
                heatmap_image_b64=BinaryContent(data=image_response.content, media_type='image/png'),
            )
        ],
        max_stops=5,
        radius_meters=4000,
    )

    output = asyncio.run(plan_trip(sample_input))
    print(output)