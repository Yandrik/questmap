from __future__ import annotations

import asyncio
import contextlib
import json
from collections.abc import AsyncIterator
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol
from uuid import uuid4

import httpx
from surrealdb import RecordID, SurrealError

from motis import MotisPlanRequest
from trip_planning_models import (
    GeoCoordinate,
    ItineraryStepDraft,
    ItineraryStepType,
    TransportMode,
    TripPlan,
    TripPlanItem,
    TripPlanningAnswer,
    TripPlanningEventPayload,
    TripPlanningQuestion,
    TripPlanningRequest,
    TripPlanningSessionSnapshot,
)
from valhalla import (
    CostingType,
    ValhallaLocation,
    ValhallaRouteRequest,
)

SESSION_TABLE = "trip_planning_session"
EVENT_TABLE = "trip_planning_event"


class TripPlanningError(Exception):
    """Base exception for trip-planning workflow failures."""


class SessionNotFoundError(TripPlanningError):
    pass


class StaleAnswerError(TripPlanningError):
    pass


class InvalidAnswerError(TripPlanningError):
    pass


class RoutePlanningError(TripPlanningError):
    pass


@dataclass(frozen=True)
class PoiCategoryFilter:
    families: tuple[str, ...] = ()
    types: tuple[str, ...] = ()


@dataclass(frozen=True)
class PoiCandidate:
    coordinate: GeoCoordinate
    primary_family: str | None = None
    primary_type: str | None = None
    distance_meters: float | None = None


@dataclass(frozen=True)
class StoredPlanningEvent:
    sequence: int
    payload: TripPlanningEventPayload
    created_at: datetime


@dataclass(frozen=True)
class RouteCandidate:
    mode: TransportMode
    duration_seconds: int
    distance_meters: float | None
    geometry: list[GeoCoordinate]
    description: str


class TripPlanningRepository(Protocol):
    async def create_session(
        self, session_id: str, request: TripPlanningRequest, now: datetime
    ) -> TripPlanningSessionSnapshot: ...

    async def get_session(self, session_id: str) -> TripPlanningSessionSnapshot: ...

    async def update_session(
        self, session_id: str, updates: dict[str, Any]
    ) -> TripPlanningSessionSnapshot: ...

    async def append_event(
        self, session_id: str, payload: TripPlanningEventPayload
    ) -> StoredPlanningEvent: ...

    async def list_events(
        self, session_id: str, after_sequence: int = -1
    ) -> list[StoredPlanningEvent]: ...

    async def search_pois(
        self,
        center: GeoCoordinate,
        radius_meters: float,
        category_filter: PoiCategoryFilter | None,
        limit: int = 5,
    ) -> list[PoiCandidate]: ...


class ValhallaRoutingClient(Protocol):
    async def route(self, route_request: ValhallaRouteRequest) -> dict[str, Any]: ...


class MotisRoutingClient(Protocol):
    async def plan(self, plan_request: MotisPlanRequest) -> dict[str, Any]: ...


class SurrealTripPlanningRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    async def create_session(
        self, session_id: str, request: TripPlanningRequest, now: datetime
    ) -> TripPlanningSessionSnapshot:
        record = {
            "sessionId": session_id,
            "draftId": request.draft_id,
            "state": "queued",
            "request": _json_model(request),
            "currentQuestion": None,
            "latestPartialPlan": None,
            "finalPlan": None,
            "lastMessage": "Queued for planning.",
            "createdAt": now.isoformat(),
            "updatedAt": now.isoformat(),
            "eventCount": 0,
        }
        await self._db.create(_session_record_id(session_id), record)
        return _snapshot_from_record(record)

    async def get_session(self, session_id: str) -> TripPlanningSessionSnapshot:
        record = await self._select_one(_session_record_id(session_id))
        if record is None:
            raise SessionNotFoundError(session_id)
        return _snapshot_from_record(record)

    async def update_session(
        self, session_id: str, updates: dict[str, Any]
    ) -> TripPlanningSessionSnapshot:
        updates = {**updates, "updatedAt": _utc_now().isoformat()}
        record = await self._db.merge(_session_record_id(session_id), updates)
        if record is None:
            raise SessionNotFoundError(session_id)
        return _snapshot_from_record(record)

    async def append_event(
        self, session_id: str, payload: TripPlanningEventPayload
    ) -> StoredPlanningEvent:
        session_record = await self._select_one(_session_record_id(session_id))
        if session_record is None:
            raise SessionNotFoundError(session_id)

        sequence = _int_value(session_record.get("eventCount")) or 0
        created_at = _utc_now()
        event_record = {
            "sessionId": session_id,
            "sequence": sequence,
            "payload": _json_model(payload),
            "createdAt": created_at.isoformat(),
        }
        await self._db.create(_event_record_id(session_id, sequence), event_record)
        await self._db.merge(
            _session_record_id(session_id),
            {
                "eventCount": sequence + 1,
                "updatedAt": created_at.isoformat(),
            },
        )
        return StoredPlanningEvent(
            sequence=sequence,
            payload=payload,
            created_at=created_at,
        )

    async def list_events(
        self, session_id: str, after_sequence: int = -1
    ) -> list[StoredPlanningEvent]:
        records = await self._db.query(
            """
            SELECT sequence, payload, createdAt
            FROM trip_planning_event
            WHERE sessionId = $session_id AND sequence > $after_sequence
            ORDER BY sequence ASC;
            """,
            {"session_id": session_id, "after_sequence": after_sequence},
        )
        if not isinstance(records, list):
            return []
        return [_event_from_record(record) for record in records]

    async def search_pois(
        self,
        center: GeoCoordinate,
        radius_meters: float,
        category_filter: PoiCategoryFilter | None,
        limit: int = 5,
    ) -> list[PoiCandidate]:
        category_clause = ""
        variables: dict[str, Any] = {
            "lat": center.lat,
            "lon": center.lon,
            "radius": radius_meters,
            "limit": limit,
        }
        if category_filter is not None:
            if category_filter.families:
                variables["families"] = list(category_filter.families)
                category_clause += " AND primary_family IN $families"
            if category_filter.types:
                variables["types"] = list(category_filter.types)
                if category_clause:
                    category_clause = (
                        " AND ("
                        + category_clause.removeprefix(" AND ")
                        + " OR primary_type IN $types)"
                    )
                else:
                    category_clause = " AND primary_type IN $types"

        try:
            records = await self._db.query(
                f"""
                SELECT name, lat, lon, primary_family, primary_type,
                  geo::distance(
                    location,
                    <point>[<float>$lon, <float>$lat]
                  ) AS distanceMeters
                FROM osm_object
                WHERE location != NONE
                  AND geo::distance(
                    location,
                    <point>[<float>$lon, <float>$lat]
                  ) <= <float>$radius
                  {category_clause}
                ORDER BY distanceMeters ASC
                LIMIT $limit;
                """,
                variables,
            )
        except SurrealError:
            return []
        if not isinstance(records, list):
            return []
        return [_poi_from_record(record) for record in records]

    async def _select_one(self, record_id: RecordID) -> dict[str, Any] | None:
        result = await self._db.select(record_id)
        if isinstance(result, list):
            if not result:
                return None
            result = result[0]
        if not isinstance(result, dict):
            return None
        result.pop("id", None)
        return result


class TripPlanningEventBus:
    def __init__(self) -> None:
        self._subscribers: dict[str, set[asyncio.Queue[None]]] = {}

    @contextlib.asynccontextmanager
    async def subscribe(self, session_id: str) -> AsyncIterator[asyncio.Queue[None]]:
        queue: asyncio.Queue[None] = asyncio.Queue()
        self._subscribers.setdefault(session_id, set()).add(queue)
        try:
            yield queue
        finally:
            subscribers = self._subscribers.get(session_id)
            if subscribers is not None:
                subscribers.discard(queue)
                if not subscribers:
                    self._subscribers.pop(session_id, None)

    def publish(self, session_id: str) -> None:
        for queue in self._subscribers.get(session_id, set()):
            queue.put_nowait(None)


class TripPlanningService:
    def __init__(
        self,
        repository: TripPlanningRepository,
        valhalla: ValhallaRoutingClient,
        motis: MotisRoutingClient,
        event_bus: TripPlanningEventBus | None = None,
    ) -> None:
        self._repository = repository
        self._planner = TripPlanner(repository, valhalla, motis)
        self._event_bus = event_bus or TripPlanningEventBus()
        self._tasks: dict[str, asyncio.Task[None]] = {}

    async def start_session(self, request: TripPlanningRequest) -> str:
        session_id = uuid4().hex
        await self._repository.create_session(session_id, request, _utc_now())
        task = asyncio.create_task(self._run_session(session_id))
        self._tasks[session_id] = task
        task.add_done_callback(lambda _: self._tasks.pop(session_id, None))
        return session_id

    async def get_session(self, session_id: str) -> TripPlanningSessionSnapshot:
        return await self._repository.get_session(session_id)

    async def answer_question(
        self, session_id: str, answer: TripPlanningAnswer
    ) -> None:
        session = await self._repository.get_session(session_id)
        question = session.current_question
        if session.state != "waitingForAnswer" or question is None:
            raise StaleAnswerError("Session is not waiting for an answer")
        if question.id != answer.question_id:
            raise StaleAnswerError("Answer does not match current question")
        _validate_answer_value(question, answer.value)
        await self._repository.update_session(
            session_id,
            {
                "state": "running",
                "currentQuestion": None,
                "lastMessage": "Applying your answer...",
            },
        )
        await self._emit(
            session_id,
            TripPlanningEventPayload(
                type="status",
                message="Applying your answer...",
            ),
        )

    async def cancel_session(self, session_id: str) -> None:
        session = await self._repository.get_session(session_id)
        if session.state in {"completed", "failed", "cancelled"}:
            return

        task = self._tasks.get(session_id)
        if task is not None:
            task.cancel()
        await self._repository.update_session(
            session_id,
            {
                "state": "cancelled",
                "currentQuestion": None,
                "lastMessage": "Planning cancelled.",
            },
        )
        await self._emit(
            session_id,
            TripPlanningEventPayload(type="done", message="done"),
        )

    async def stream_events(self, session_id: str) -> AsyncIterator[str]:
        await self._repository.get_session(session_id)
        next_sequence = -1
        async with self._event_bus.subscribe(session_id) as queue:
            while True:
                events = await self._repository.list_events(
                    session_id, after_sequence=next_sequence
                )
                for event in events:
                    next_sequence = event.sequence
                    yield _sse(event.payload)
                    if event.payload.type == "done":
                        return

                try:
                    await asyncio.wait_for(queue.get(), timeout=15)
                except TimeoutError:
                    yield ": keepalive\n\n"

    async def close(self) -> None:
        tasks = list(self._tasks.values())
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def _run_session(self, session_id: str) -> None:
        try:
            await self._repository.update_session(
                session_id,
                {
                    "state": "running",
                    "lastMessage": "Finding places near your route...",
                },
            )
            await self._emit(
                session_id,
                TripPlanningEventPayload(
                    type="status",
                    message="Finding places near your route...",
                ),
            )
            await self._raise_if_cancelled(session_id)

            plan = await self._planner.build_plan(session_id)
            await self._repository.update_session(
                session_id,
                {
                    "state": "completed",
                    "finalPlan": _json_model(plan),
                    "latestPartialPlan": _json_model(plan),
                    "lastMessage": "Trip plan ready.",
                },
            )
            await self._emit(
                session_id,
                TripPlanningEventPayload(
                    type="finalPlan",
                    message="Trip plan ready.",
                    plan=plan,
                ),
            )
            await self._emit(
                session_id,
                TripPlanningEventPayload(type="done", message="done"),
            )
        except asyncio.CancelledError:
            with contextlib.suppress(SessionNotFoundError):
                session = await self._repository.get_session(session_id)
                if session.state != "cancelled":
                    await self._repository.update_session(
                        session_id,
                        {
                            "state": "cancelled",
                            "lastMessage": "Planning cancelled.",
                        },
                    )
                    await self._emit(
                        session_id,
                        TripPlanningEventPayload(type="done", message="done"),
                    )
            raise
        except Exception as exc:
            message = str(exc) or "Trip planning failed."
            await self._repository.update_session(
                session_id,
                {
                    "state": "failed",
                    "currentQuestion": None,
                    "lastMessage": message,
                },
            )
            await self._emit(
                session_id,
                TripPlanningEventPayload(type="error", message=message),
            )
            await self._emit(
                session_id,
                TripPlanningEventPayload(type="done", message="done"),
            )

    async def _emit(
        self, session_id: str, payload: TripPlanningEventPayload
    ) -> StoredPlanningEvent:
        event = await self._repository.append_event(session_id, payload)
        self._event_bus.publish(session_id)
        return event

    async def _raise_if_cancelled(self, session_id: str) -> None:
        session = await self._repository.get_session(session_id)
        if session.state == "cancelled":
            raise asyncio.CancelledError


class TripPlanner:
    def __init__(
        self,
        repository: TripPlanningRepository,
        valhalla: ValhallaRoutingClient,
        motis: MotisRoutingClient,
    ) -> None:
        self._repository = repository
        self._valhalla = valhalla
        self._motis = motis

    async def build_plan(self, session_id: str) -> TripPlan:
        session = await self._repository.get_session(session_id)
        request = session.request
        cursor = request.start_location
        current_time = _initial_time(request)
        items: list[TripPlanItem] = []

        for index, step in enumerate(request.steps, start=1):
            activity_location = await self._resolve_activity_location(step, cursor)
            if not _same_place(cursor, activity_location):
                route = await self._route_between(
                    cursor,
                    activity_location,
                    request.transport_modes,
                    current_time,
                )
                travel_start = current_time
                travel_end = current_time + timedelta(seconds=route.duration_seconds)
                items.append(
                    TripPlanItem(
                        id=f"travel-{index}",
                        type="travel",
                        title=f"Travel to {step.title}",
                        description=route.description,
                        reasoning="Selected as the fastest reachable route.",
                        transport_mode=route.mode,
                        start_time=travel_start,
                        end_time=travel_end,
                        geometry=route.geometry,
                    )
                )
                current_time = travel_end

            activity_start = _activity_start_time(step, current_time)
            activity_end = activity_start + timedelta(
                minutes=step.time.duration_minutes
            )
            items.append(
                TripPlanItem(
                    id=f"activity-{index}",
                    type="activity",
                    title=step.title,
                    description=step.details or step.title,
                    reasoning=_activity_reasoning(step, activity_location),
                    source_draft_step_id=step.id,
                    step_type=step.type,
                    start_time=activity_start,
                    end_time=activity_end,
                    location=activity_location,
                    geometry=[],
                )
            )
            cursor = activity_location
            current_time = activity_end

        if request.end_location is not None and not _same_place(
            cursor, request.end_location
        ):
            route = await self._route_between(
                cursor,
                request.end_location,
                request.transport_modes,
                current_time,
            )
            items.append(
                TripPlanItem(
                    id="travel-final",
                    type="travel",
                    title="Travel to final destination",
                    description=route.description,
                    reasoning="Connects the itinerary to the requested end point.",
                    transport_mode=route.mode,
                    start_time=current_time,
                    end_time=current_time + timedelta(seconds=route.duration_seconds),
                    geometry=route.geometry,
                )
            )

        title = _plan_title(request)
        return TripPlan(
            id=f"plan-{session_id}",
            title=title,
            summary=f"{len(request.steps)} planned stops with routed travel legs.",
            items=items,
        )

    async def _resolve_activity_location(
        self, step: ItineraryStepDraft, cursor: GeoCoordinate
    ) -> GeoCoordinate:
        constraint = step.location
        if constraint.type == "exactPoint" and constraint.point is not None:
            return _with_default_label(constraint.point, step.title)

        if constraint.type == "aroundPoint" and constraint.point is not None:
            center = constraint.point
            radius_meters = 750.0
        elif constraint.type == "areaCircle" and constraint.center is not None:
            center = constraint.center
            radius_meters = constraint.radius_meters or 1000.0
        else:
            center = cursor
            minutes = constraint.max_transport_minutes or 15
            radius_meters = max(500.0, min(minutes * 80.0, 5000.0))

        candidates = await self._repository.search_pois(
            center=center,
            radius_meters=radius_meters,
            category_filter=_category_filter(step.type),
            limit=5,
        )
        if candidates:
            return _with_default_label(candidates[0].coordinate, step.title)
        return _with_default_label(center, step.title)

    async def _route_between(
        self,
        start: GeoCoordinate,
        destination: GeoCoordinate,
        modes: list[TransportMode],
        depart_at: datetime,
    ) -> RouteCandidate:
        candidates: list[RouteCandidate] = []
        for mode in modes:
            try:
                if mode == "publicTransport":
                    candidates.append(
                        await self._route_with_motis(start, destination, depart_at)
                    )
                else:
                    candidates.append(
                        await self._route_with_valhalla(start, destination, mode)
                    )
            except (
                RoutePlanningError,
                httpx.HTTPError,
                KeyError,
                ValueError,
                TypeError,
            ):
                continue

        if not candidates:
            raise RoutePlanningError(
                "No reachable route was found for a required trip leg."
            )
        return min(candidates, key=lambda candidate: candidate.duration_seconds)

    async def _route_with_valhalla(
        self,
        start: GeoCoordinate,
        destination: GeoCoordinate,
        mode: TransportMode,
    ) -> RouteCandidate:
        costing = _valhalla_costing(mode)
        response = await self._valhalla.route(
            ValhallaRouteRequest(
                locations=[
                    ValhallaLocation(
                        lat=start.lat,
                        lon=start.lon,
                        name=start.label,
                    ),
                    ValhallaLocation(
                        lat=destination.lat,
                        lon=destination.lon,
                        name=destination.label,
                    ),
                ],
                costing=costing,
                shape_format="geojson",
                directions_type="none",
                alternates=0,
            )
        )
        trip = _dict_value(response.get("trip"))
        if trip is None:
            raise RoutePlanningError("Valhalla response did not contain a trip")
        summary = _dict_value(trip.get("summary")) or {}
        duration = _int_value(summary.get("time")) or 0
        length_km = _float_value(summary.get("length"))
        geometry = [
            *_coordinates_from_any(trip.get("shape")),
            *_coordinates_from_valhalla_legs(trip.get("legs")),
        ]
        return RouteCandidate(
            mode=mode,
            duration_seconds=duration,
            distance_meters=None if length_km is None else length_km * 1000,
            geometry=geometry,
            description=_route_description(mode, duration, length_km),
        )

    async def _route_with_motis(
        self,
        start: GeoCoordinate,
        destination: GeoCoordinate,
        depart_at: datetime,
    ) -> RouteCandidate:
        response = await self._motis.plan(
            MotisPlanRequest(
                fromPlace=_motis_place(start),
                toPlace=_motis_place(destination),
                time=depart_at,
                detailedLegs=True,
                detailedTransfers=True,
                directModes=[],
                preTransitModes=["WALK"],
                postTransitModes=["WALK"],
                transitModes=["TRANSIT"],
                numItineraries=1,
                numLegAlternatives=0,
                timetableView=False,
                language=["de", "en"],
            )
        )
        itineraries = response.get("itineraries")
        if not isinstance(itineraries, list) or not itineraries:
            raise RoutePlanningError("MOTIS response did not contain itineraries")
        itinerary = _dict_value(itineraries[0])
        if itinerary is None:
            raise RoutePlanningError("MOTIS itinerary was not an object")
        legs = itinerary.get("legs")
        duration = _int_value(itinerary.get("duration"))
        if duration is None:
            duration = _motis_legs_duration(legs)
        distance = _motis_legs_distance(legs)
        geometry = _coordinates_from_motis_legs(legs)
        return RouteCandidate(
            mode="publicTransport",
            duration_seconds=duration,
            distance_meters=distance,
            geometry=geometry,
            description=_motis_description(legs, duration),
        )


def _validate_answer_value(question: TripPlanningQuestion, value: Any) -> None:
    if question.kind == "yesNo" and not isinstance(value, bool):
        raise InvalidAnswerError("yesNo answers must be boolean")
    if question.kind == "number" and not isinstance(value, int | float):
        raise InvalidAnswerError("number answers must be numeric")
    if question.kind == "text" and not isinstance(value, str):
        raise InvalidAnswerError("text answers must be strings")
    if question.kind in {"selection", "routeChoice"}:
        valid_ids = {option.id for option in question.options}
        if isinstance(value, str) and (not valid_ids or value in valid_ids):
            return
        if isinstance(value, dict):
            return
        raise InvalidAnswerError("selection answers must reference an option")


def _sse(payload: TripPlanningEventPayload) -> str:
    data = payload.model_dump_json(by_alias=True, exclude_none=True)
    return f"event: {payload.type}\ndata: {data}\n\n"


def _json_model(model: Any) -> dict[str, Any]:
    return json.loads(model.model_dump_json(by_alias=True, exclude_none=True))


def _snapshot_from_record(record: dict[str, Any]) -> TripPlanningSessionSnapshot:
    clean = dict(record)
    clean.pop("id", None)
    clean.pop("eventCount", None)
    return TripPlanningSessionSnapshot.model_validate(clean)


def _event_from_record(record: Any) -> StoredPlanningEvent:
    if not isinstance(record, dict):
        raise ValueError("Expected event record")
    return StoredPlanningEvent(
        sequence=_int_value(record.get("sequence")) or 0,
        payload=TripPlanningEventPayload.model_validate(record.get("payload")),
        created_at=_datetime_value(record.get("createdAt")),
    )


def _poi_from_record(record: Any) -> PoiCandidate:
    if not isinstance(record, dict):
        raise ValueError("Expected POI record")
    label = _str_value(record.get("name"))
    return PoiCandidate(
        coordinate=GeoCoordinate(
            lat=_float_value(record.get("lat")) or 0,
            lon=_float_value(record.get("lon")) or 0,
            label=label,
        ),
        primary_family=_str_value(record.get("primary_family")),
        primary_type=_str_value(record.get("primary_type")),
        distance_meters=_float_value(record.get("distanceMeters")),
    )


def _session_record_id(session_id: str) -> RecordID:
    return RecordID(SESSION_TABLE, session_id)


def _event_record_id(session_id: str, sequence: int) -> RecordID:
    return RecordID(EVENT_TABLE, f"{session_id}_{sequence:08d}")


def _utc_now() -> datetime:
    return datetime.now(UTC)


def _datetime_value(value: Any) -> datetime:
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        return datetime.fromisoformat(value)
    raise ValueError("Expected datetime")


def _initial_time(request: TripPlanningRequest) -> datetime:
    first_start = next(
        (step.time.start_time for step in request.steps if step.time.start_time),
        None,
    )
    return _ensure_aware(first_start) if first_start is not None else _utc_now()


def _activity_start_time(step: ItineraryStepDraft, current_time: datetime) -> datetime:
    start = step.time.start_time
    if start is None and step.time.arrival_time is not None:
        start = step.time.arrival_time - timedelta(minutes=step.time.duration_minutes)
    if start is None:
        return current_time
    return max(current_time, _ensure_aware(start))


def _ensure_aware(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value


def _plan_title(request: TripPlanningRequest) -> str:
    if len(request.steps) == 1:
        return request.steps[0].title
    return f"{len(request.steps)} stop trip"


def _activity_reasoning(
    step: ItineraryStepDraft, coordinate: GeoCoordinate
) -> str | None:
    label = coordinate.label
    if label is None:
        return "Selected from the requested location constraint."
    return f"Selected {label} for the requested {step.type} stop."


def _category_filter(step_type: ItineraryStepType) -> PoiCategoryFilter | None:
    return {
        "eat": PoiCategoryFilter(
            families=("amenity",),
            types=("restaurant", "cafe", "fast_food", "bar", "pub"),
        ),
        "shop": PoiCategoryFilter(families=("shop",)),
        "party": PoiCategoryFilter(
            families=("amenity",),
            types=("bar", "pub", "nightclub"),
        ),
        "sightsee": PoiCategoryFilter(
            families=("tourism", "historic"),
            types=("museum", "attraction", "viewpoint", "monument"),
        ),
        "walk": PoiCategoryFilter(families=("leisure", "tourism", "natural")),
        "meander": PoiCategoryFilter(
            families=("shop", "amenity", "tourism", "historic", "leisure"),
        ),
        "exactLocation": None,
    }[step_type]


def _with_default_label(coordinate: GeoCoordinate, label: str) -> GeoCoordinate:
    if coordinate.label:
        return coordinate
    return coordinate.model_copy(update={"label": label})


def _same_place(first: GeoCoordinate, second: GeoCoordinate) -> bool:
    return (
        abs(first.lat - second.lat) < 0.00001 and abs(first.lon - second.lon) < 0.00001
    )


def _valhalla_costing(mode: TransportMode) -> CostingType:
    if mode == "walk":
        return "pedestrian"
    if mode == "bike":
        return "bicycle"
    if mode == "drive":
        return "auto"
    raise ValueError("publicTransport does not use Valhalla")


def _motis_place(coordinate: GeoCoordinate) -> str:
    return f"{coordinate.lat},{coordinate.lon}"


def _route_description(
    mode: TransportMode, duration_seconds: int, length_km: float | None
) -> str:
    distance = "" if length_km is None else f" over {length_km:.1f} km"
    return f"{mode} route{distance}, about {_minutes(duration_seconds)} min."


def _motis_description(legs: Any, duration_seconds: int) -> str:
    names: list[str] = []
    if isinstance(legs, list):
        for raw_leg in legs:
            leg = _dict_value(raw_leg)
            if leg is None:
                continue
            name = (
                _str_value(leg.get("displayName"))
                or _str_value(leg.get("routeShortName"))
                or _str_value(leg.get("routeLongName"))
            )
            if name:
                names.append(name)
    prefix = " + ".join(names) if names else "Public transport"
    return f"{prefix}, about {_minutes(duration_seconds)} min."


def _minutes(duration_seconds: int) -> int:
    return round(duration_seconds / 60)


def _coordinates_from_valhalla_legs(raw_legs: Any) -> list[GeoCoordinate]:
    if not isinstance(raw_legs, list):
        return []
    coordinates: list[GeoCoordinate] = []
    for raw_leg in raw_legs:
        leg = _dict_value(raw_leg)
        if leg is not None:
            coordinates.extend(_coordinates_from_any(leg.get("shape")))
    return coordinates


def _coordinates_from_motis_legs(raw_legs: Any) -> list[GeoCoordinate]:
    if not isinstance(raw_legs, list):
        return []
    coordinates: list[GeoCoordinate] = []
    for raw_leg in raw_legs:
        leg = _dict_value(raw_leg)
        if leg is not None:
            coordinates.extend(_coordinates_from_motis_geometry(leg.get("legGeometry")))
    return coordinates


def _motis_legs_duration(raw_legs: Any) -> int:
    if not isinstance(raw_legs, list):
        return 0
    return sum(
        _int_value(leg.get("duration")) or 0
        for raw_leg in raw_legs
        if (leg := _dict_value(raw_leg)) is not None
    )


def _motis_legs_distance(raw_legs: Any) -> float | None:
    if not isinstance(raw_legs, list):
        return None
    total = 0.0
    for raw_leg in raw_legs:
        leg = _dict_value(raw_leg)
        if leg is not None:
            total += _float_value(leg.get("distance")) or 0
    return total or None


def _coordinates_from_motis_geometry(value: Any) -> list[GeoCoordinate]:
    geometry = _dict_value(value)
    if geometry is None:
        return []
    points = _str_value(geometry.get("points"))
    precision = _int_value(geometry.get("precision")) or 6
    if not points:
        return []
    return _decode_polyline(points, precision)


def _coordinates_from_any(value: Any) -> list[GeoCoordinate]:
    if value is None:
        return []
    if isinstance(value, str):
        return _decode_polyline(value, 6)
    mapping = _dict_value(value)
    if mapping is None:
        return []
    geometry = _dict_value(mapping.get("geometry")) or mapping
    if geometry.get("type") != "LineString":
        return []
    raw_coordinates = geometry.get("coordinates")
    if not isinstance(raw_coordinates, list):
        return []
    return [
        GeoCoordinate(
            lon=_float_value(raw_coordinate[0]) or 0,
            lat=_float_value(raw_coordinate[1]) or 0,
        )
        for raw_coordinate in raw_coordinates
        if isinstance(raw_coordinate, list) and len(raw_coordinate) >= 2
    ]


def _decode_polyline(encoded: str, precision: int) -> list[GeoCoordinate]:
    factor = 10**precision
    coordinates: list[GeoCoordinate] = []
    index = 0
    lat = 0
    lon = 0
    while index < len(encoded):
        lat_delta, index = _decode_polyline_value(encoded, index)
        lon_delta, index = _decode_polyline_value(encoded, index)
        lat += lat_delta
        lon += lon_delta
        coordinates.append(GeoCoordinate(lat=lat / factor, lon=lon / factor))
    return coordinates


def _decode_polyline_value(encoded: str, start_index: int) -> tuple[int, int]:
    index = start_index
    result = 0
    shift = 0
    while True:
        byte = ord(encoded[index]) - 63
        index += 1
        result |= (byte & 0x1F) << shift
        shift += 5
        if byte < 0x20 or index >= len(encoded):
            break
    value = ~(result >> 1) if result & 1 else result >> 1
    return value, index


def _dict_value(value: Any) -> dict[str, Any] | None:
    if isinstance(value, dict):
        return value
    return None


def _str_value(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value)
    return text if text else None


def _int_value(value: Any) -> int | None:
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return round(value)
    if isinstance(value, str):
        return int(value) if value.isdigit() else None
    return None


def _float_value(value: Any) -> float | None:
    if isinstance(value, int | float):
        return float(value)
    if isinstance(value, str):
        with contextlib.suppress(ValueError):
            return float(value)
    return None
