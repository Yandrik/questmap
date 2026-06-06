from __future__ import annotations

import base64
import json
from dataclasses import dataclass
from typing import Literal

from pydantic import BaseModel, Field
from pydantic_ai import Agent
from surrealdb import AsyncSurreal


class GeoPoint(BaseModel):
    name: str
    lat: float
    lon: float
    category: Literal["shop", "restaurant", "sightseeing", "transit", "other"]
    reason: str
    confidence: float = Field(..., ge=0, le=1)


class TripPlanOutput(BaseModel):
    summary: str
    ordered_points: list[GeoPoint]
    route_strategy: str
    warnings: list[str] = []


class TripPlanInput(BaseModel):
    city: str
    start_point: tuple[float, float]
    end_point: tuple[float, float]
    trip_type: Literal["shopping", "food", "sightseeing", "mixed"]
    max_stops: int = 5
    radius_meters: int = 2000
    notes: str | None = None
    heatmap_image_b64: str
    map_image_b64: str | None = None


@dataclass
class Deps:
    db_url: str
    db_ns: str
    db_name: str
    db_user: str
    db_pass: str


agent = Agent(
    "openai-compatible:http://bananabread.duckdns.org/ayvim/v1",
    output_type=TripPlanOutput,
)


@agent.tool_plain
async def search_pois(city: str, lat: float, lon: float, radius_meters: int, category: str | None = None) -> str:
    """
    Search SurrealDB for nearby points of interest around a geo coordinate.
    Returns JSON string with candidate POIs.
    """
    async with AsyncSurreal("ws://your-surrealdb-host:8000/rpc") as db:
        await db.signin({"username": "root", "password": "root"})
        await db.use("trip_planner", "pois")

        if category:
            query = """
            SELECT id, name, lat, lon, category, rating, tags
            FROM poi
            WHERE city = $city
              AND category = $category
              AND geo::distance((lat, lon), ($lat, $lon)) < $radius
            LIMIT 20;
            """
            vars_ = {"city": city, "category": category, "lat": lat, "lon": lon, "radius": radius_meters}
        else:
            query = """
            SELECT id, name, lat, lon, category, rating, tags
            FROM poi
            WHERE city = $city
              AND geo::distance((lat, lon), ($lat, $lon)) < $radius
            LIMIT 20;
            """
            vars_ = {"city": city, "lat": lat, "lon": lon, "radius": radius_meters}

        result = await db.query(query, vars_)
        return json.dumps(result, ensure_ascii=False)


async def plan_trip(inp: TripPlanInput) -> TripPlanOutput:
    prompt = f"""
Plan a city trip route using the heatmap image and map context.

City: {inp.city}
Start: {inp.start_point}
End: {inp.end_point}
Trip type: {inp.trip_type}
Max stops: {inp.max_stops}
Radius: {inp.radius_meters} meters
Notes: {inp.notes or ""}

Instructions:
- Interpret the heatmap to identify dense commercial or interesting areas.
- Use the map image context if provided.
- Prefer points that make a reasonable route from start to end.
- Call search_pois to verify candidate places and enrich with geolocations.
- Return only structured output in the required schema.
"""

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
        message_history=[
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/png;base64,{inp.heatmap_image_b64}"},
                    },
                ],
            }
        ],
    )
    return result.output