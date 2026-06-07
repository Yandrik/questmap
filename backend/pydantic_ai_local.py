from __future__ import annotations

import base64
import json
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from os import getenv
from typing import Any, Literal

from dotenv import load_dotenv

from pydantic import BaseModel, ConfigDict, Field, field_validator
from pydantic_ai import Agent, BinaryContent, RunContext
from pydantic_ai.models.openai import OpenAIChatModel, OpenAIResponsesModelSettings
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
    #model_config = ConfigDict(populate_by_name=True, extra="allow")

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

    '''def to_locations_of_interest(self) -> TripLocations:
        return TripLocations(
            city=(self.properties.address.city if self.properties.address else None)
            or self.properties.name
            or "",
            lat=self.geometry.coordinates[1],
            lon=self.geometry.coordinates[0],
            category="other",
        )'''


class TripPlanInput(BaseModel):
    start_point: tuple[float, float]
    end_point: tuple[float, float]
    trip_locations: list[TripLocations]
    max_stops: int = 30
    radius_meters: int = 5000

    '''@field_validator("trip_locations", mode="before")
    @classmethod
    def _normalize_geojson_feature(cls, value: Any) -> Any:
        if isinstance(value, dict) and value.get("type") == "Feature":
            return [LocationsObject.model_validate(value).to_locations_of_interest()]
        return value'''


class TripPlanOutput(BaseModel):
    summary: str
    start_point: tuple[float, float]
    end_point: tuple[float, float]
    ordered_points: list[list[LocationsObject] | LocationsObject]
    route_strategy: str
    notes: str | None = None
    warnings: list[str] = Field(default_factory=list)


PromptType = Literal["yesNo", "number", "text", "selection", "routeChoice"]
AskUserCallback = Callable[
    [
        str,
        PromptType,
        str,
        list[str | dict[str, Any]] | None,
    ],
    Awaitable[Any],
]
AskUserCallbackOrNone = AskUserCallback | None


@dataclass(frozen=True)
class Deps:
    db_url: str
    db_ns: str
    db_name: str
    db_user: str
    db_pass: str
    session_id: str | None = None
    ask_user: AskUserCallbackOrNone = None


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
            "osm_id": item.get("osm_id"),
            "name": item.get("name"),
            "lat": item.get("lat"),
            "lon": item.get("lon"),
            "distance_m": item.get("distance_m"),
            "family": item.get("primary_family"),
            "category": item.get("primary_type")
            or (item.get("tags") or {}).get("category"),
        }
        for item in serializable_result
        if isinstance(item, dict)
    ]
    #print(f"search_pois result: {filtered_result}")
    return json.dumps(filtered_result, ensure_ascii=False)

async def search_closest_city(
    lat: float,
    lon: float,
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
        query, variables = _closest_city_query(lat, lon)
        result = await db.query(query, variables)

    serializable_result = _jsonable(result)
    filtered_result = [
        {
            "lat": item.get("lat"),
            "lon": item.get("lon"),
            "city": item.get("address", {}).get("city", None),
        }
        for item in serializable_result
        if isinstance(item, dict)
    ]
    #print(f"search_pois result: {filtered_result}")
    return json.dumps(filtered_result, ensure_ascii=False)


async def prompt_user(
    ctx: RunContext[Deps],
    prompt_type: PromptType,
    message: str,
    suggestions: list[str | dict[str, Any]] | None = None,
) -> str:
    """Non-blocking placeholder for agent clarification prompts."""
    if ctx.deps.ask_user is None or ctx.deps.session_id is None:
        print(f"Prompting user {prompt_type}: {message},\n{suggestions}")
        return (
            f"Question deferred to API workflow: {message}\n"
            "Just use the first object in the list of suggestions as the answer "
            "to the question."
        )

    answer = await ctx.deps.ask_user(
        ctx.deps.session_id,
        prompt_type,
        message,
        suggestions,
    )
    return json.dumps(answer, ensure_ascii=False)


async def plan_trip(
    inp: TripPlanInput,
    session_id: str | None = None,
    ask_user: AskUserCallbackOrNone = None,
) -> TripPlanOutput:
    agent = _build_agent()
    prompt = _planning_prompt(inp)
    result = await agent.run(
        prompt,
        deps=Deps(
            db_url=getenv("SURREALDB_URL", "ws://localhost:8001"),
            db_ns=getenv("SURREALDB_NAMESPACE", "main"),
            db_name=getenv("SURREALDB_DATABASE", "main"),
            db_user=getenv("SURREALDB_USERNAME", "root"),
            db_pass=getenv("SURREALDB_PASSWORD", "root"),
            session_id=session_id,
            ask_user=ask_user,
        ),
        #model_settings={"temperature": 0.2},
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
    settings = OpenAIResponsesModelSettings(
        openai_reasoning_effort="low",
        openai_reasoning_summary='concise',
    )
    agent: Agent[Any, Any] = Agent(
        model=model,
        model_settings=settings,
        output_type=TripPlanOutput,
        system_prompt="You're a helpful local trip-planning assistant.",
    )
    agent.tool_plain(search_pois)
    #agent.tool_plain(search_closest_city)
    agent.tool(prompt_user, sequential=True)
    return agent


def _planning_prompt(inp: TripPlanInput) -> str:
    prompt = f"""
Plan a city trip route using the heatmap image and map context.

Start: {inp.start_point}
End: {inp.end_point}
Trip Locations: {inp.trip_locations}
Max stops: {inp.max_stops}
Radius: {inp.radius_meters} meters

You are a capable trip planer that want to help people to plan a trip through a city.
The people count on you and you should do exactly that what is prompet so you can fulfill your task as best as you can.

As an input you get an object with a few variables.
The first variable is the starting_point, and marks the location where the people currently are. The points are given in the format (lat, long).
The second variable is the end_point, and it marks the final destination of the group.

You are also given a time frame, in which you have to work with, to get all things done that the people want to do. If the people spend to much time or too little
time with their activity, politely inform them about this and give alternative solution.

The most important part are the trip_locations. This is an ordered list of all things the people want to do in the time frame. The order of the trip locations are
very important and should be considered the same when creating the output.

Each Trip Locations object has a city, latitude and longitude of the central point, which with the radius_meters from the TripPlanInput object form an area, in
which the activities for each trip location should be contained. Next to that a catrgory variable is also used to filter for the correct activities. All objects,
that fit in the criteria are automatically filtered in the search query to the data base, so you don't have to worry about that.

Your job is now to chose the best locationsObjects (multiple) that the query gave back. These should fit as best as you can to the notes provided. If no notes are provided
then prompt the user, using the prompt_user tool, what his preferences are. For the category restaurant these can be certain food types like "pizza" or "fried rice". For shopping this can be
something like "shoes" or "sports gear" or "food". Be creative about your suggestions as the people will like creative and thoughtful suggestions.
After you got the input you can now chose the best locationsObjects (multiple).
IT IS VERY IMPORTANT THAT EVERY SUGGESTION ALSO EXISTS IN THE QUERY RESULT!!!!!!

You choose up to 6 items (more are better), that you think fits best to their trip. Use the prompt_user tool for that, with a list of osm_ids,
to ask the people what locations they want to visit. DO THIS FOR EACH TRIP LOCATION! The people can then decide for one or more locations they want to visit.
FOR EACH TRIP LOCATION ASK THE USER TO CHOOSE FROM THE LOCATIONS THAT ARE IN THE QUERY RESULT AND FIT BEST TO THEIR NOTES AND PREFERENCES.

If the people choose more than one location put the locationsObject objects inside a list.

All the information you get from the query about the locations should be used to fill the properties of the locationsObject, so that the people get a good overview
about the location and can make a good decision.

Repeat this for each Trip location object in the list and create list with all locationsObjects and lists of locationsObjects.
DO NOT FORGET TO ASK THE USER FOR HIS PREFERED LOCATIONS OF THE UP TO 6 YOU CHOSE AND DO THIS FOR EACH TRIP LOCATION OBJECT IN THE LIST.

If you are unsure about something prompt the user with some suggestions.

You are a good trip planer and you got this :)

User prompts can be of the following types:
- ('yesNo', message (e.g., "Do you want to visit this location?")) -> boolean.
- ('number', message (e.g., "How many people are in your group?")) -> number.
- ('text', message (e.g., "Please describe your preferences:")) -> string.
- ('selection', message (e.g., "Please select an option:")) -> option id string, or an object if the backend explicitly defines a richer option payload.
- ('routeChoice', message (e.g., "Please choose a route:")) -> selected route/option id string, or a route-choice object if specified in the question payload.

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
    if category == "sightseeing":
        category = ["tourism", "historic"]
    else: category = [category]
    category_clause = (
        """
        AND (primary_type in $category OR tags.category in $category OR primary_family in $category)
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
    LIMIT 40;
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


def _closest_city_query(lat: float, lon: float) -> tuple[str, dict[str, Any]]:
    query = """
    SELECT name, lat, lon, address.city,
      geo::distance(location, <point>[<float>$lon, <float>$lat]) AS distance_m
    FROM osm_object
    WHERE location != NONE
    AND address.city != None
    ORDER BY distance_m ASC
    LIMIT 1;
    """
    return (
        query,
        {
            "lat": lat,
            "lon": lon,
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

    load_dotenv()  # Load environment variables from .env file
    sample_input = TripPlanInput(
        start_point=(48.398678, 9.983708),
        end_point=(48.398678, 9.983708),
        trip_locations=[
            TripLocations(
                city="Ulm",
                lat=48.400833,
                lon=9.987222,
                category="restaurant",
                notes="Fried Rices and Noodles, preferably with a vegan option",
            ),
            TripLocations(
                city="Ulm",
                lat=48.400833,
                lon=9.987222,
                category="shop",
                notes="Cloths",
            ),
            TripLocations(
                city="Ulm",
                lat=48.400833,
                lon=9.987222,
                category="sightseeing",
                notes="Ulmer Münster",
            ),
            TripLocations(
                city="Ulm",
                lat=48.400833,
                lon=9.987222,
                category="restaurant",
                notes="Ice cream",
            ),
            TripLocations(
                city="Ulm",
                lat=48.400833,
                lon=9.987222,
                category="sightseeing",
                notes="Spaceport",
            )
        ],
        max_stops=5,
        radius_meters=8000,
    )

    print(asyncio.run(plan_trip(sample_input)))
