from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import math
from collections.abc import AsyncIterator
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from itertools import pairwise
from os import getenv
from typing import Any, Protocol
from uuid import uuid4

import httpx
from surrealdb import Datetime, RecordID, SurrealError

from motis import MotisPlanRequest
from trip_planning_models import (
    GeoCoordinate,
    ItineraryStepDraft,
    ItineraryStepType,
    LocationConstraint,
    TransitLegDetails,
    TransportMode,
    TripPlan,
    TripPlanItem,
    TripPlanningAnswer,
    TripPlanningEventPayload,
    TripPlanningQuestion,
    TripPlanningQuestionKind,
    TripPlanningRequest,
    TripPlanningSessionSnapshot,
    TripQuestionOption,
    TripRouteSegment,
)
from valhalla import (
    CostingType,
    ValhallaLocation,
    ValhallaRouteRequest,
)

SESSION_TABLE = "trip_planning_session"
EVENT_TABLE = "trip_planning_event"
ROUTE_CANDIDATE_TABLE = "trip_planning_route_candidate"
NEARBY_DIRECT_WALK_METERS = 15.0
TRIP_PLANNING_OPTION_LIMIT = 6
VALHALLA_ALTERNATE_COUNT = 3
MOTIS_ITINERARY_COUNT = 4
MOTIS_LEG_ALTERNATIVE_COUNT = 3

logger = logging.getLogger(__name__)


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
    id: str
    session_id: str
    leg_key: str
    start: GeoCoordinate
    destination: GeoCoordinate
    mode: TransportMode
    duration_seconds: int
    distance_meters: float | None
    geometry: list[GeoCoordinate]
    description: str
    segments: list[TripRouteSegment]
    provider: str
    depart_at: datetime | None = None
    arrive_by: datetime | None = None
    raw_provider_payload: dict[str, Any] | None = None
    selected_at: datetime | None = None
    created_at: datetime | None = None


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

    async def create_route_candidate(
        self, candidate: RouteCandidate
    ) -> RouteCandidate: ...

    async def list_route_candidates(
        self, session_id: str, leg_key: str | None = None
    ) -> list[RouteCandidate]: ...

    async def get_route_candidate(
        self, session_id: str, candidate_id: str
    ) -> RouteCandidate: ...

    async def mark_route_candidate_selected(
        self, session_id: str, candidate_id: str, selected_at: datetime
    ) -> RouteCandidate: ...


class ValhallaRoutingClient(Protocol):
    async def route(self, route_request: ValhallaRouteRequest) -> dict[str, Any]: ...


class MotisRoutingClient(Protocol):
    async def plan(self, plan_request: MotisPlanRequest) -> dict[str, Any]: ...


class PlanningEngine(Protocol):
    async def build_plan(self, session_id: str) -> TripPlan: ...


class SurrealTripPlanningRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    async def create_session(
        self, session_id: str, request: TripPlanningRequest, now: datetime
    ) -> TripPlanningSessionSnapshot:
        logger.info(
            "Creating trip-planning session session_id=%s draft_id=%s "
            "planner_mode=%s steps=%s modes=%s",
            session_id,
            request.draft_id,
            request.planner_mode,
            len(request.steps),
            request.transport_modes,
        )
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
        logger.debug(
            "Updating trip-planning session session_id=%s fields=%s state=%s",
            session_id,
            sorted(updates.keys()),
            updates.get("state"),
        )
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
        logger.info(
            "Appended trip-planning event session_id=%s sequence=%s type=%s message=%s",
            session_id,
            sequence,
            payload.type,
            payload.message,
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

        logger.debug(
            "Searching POIs center=%s radius_meters=%.0f families=%s types=%s limit=%s",
            _coord_log(center),
            radius_meters,
            category_filter.families if category_filter else (),
            category_filter.types if category_filter else (),
            limit,
        )
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
            logger.exception(
                "POI search failed center=%s radius_meters=%.0f",
                _coord_log(center),
                radius_meters,
            )
            return []
        if not isinstance(records, list):
            logger.warning(
                "POI search returned unexpected result type=%s", type(records)
            )
            return []
        candidates = [_poi_from_record(record) for record in records]
        logger.info(
            "POI search completed center=%s radius_meters=%.0f count=%s",
            _coord_log(center),
            radius_meters,
            len(candidates),
        )
        return candidates

    async def create_route_candidate(self, candidate: RouteCandidate) -> RouteCandidate:
        record = _route_candidate_record(candidate)
        await self._db.create(_route_candidate_record_id(candidate.id), record)
        logger.info(
            "Stored route candidate session_id=%s leg_key=%s candidate_id=%s "
            "mode=%s duration_seconds=%s",
            candidate.session_id,
            candidate.leg_key,
            candidate.id,
            candidate.mode,
            candidate.duration_seconds,
        )
        return _route_candidate_from_record({**record, "id": candidate.id})

    async def list_route_candidates(
        self, session_id: str, leg_key: str | None = None
    ) -> list[RouteCandidate]:
        leg_clause = "AND legKey = $leg_key" if leg_key is not None else ""
        variables: dict[str, Any] = {"session_id": session_id}
        if leg_key is not None:
            variables["leg_key"] = leg_key
        records = await self._db.query(
            f"""
            SELECT *
            FROM trip_planning_route_candidate
            WHERE sessionId = $session_id {leg_clause}
            ORDER BY createdAt ASC;
            """,
            variables,
        )
        if not isinstance(records, list):
            return []
        return [_route_candidate_from_record(record) for record in records]

    async def get_route_candidate(
        self, session_id: str, candidate_id: str
    ) -> RouteCandidate:
        record = await self._select_one(_route_candidate_record_id(candidate_id))
        if record is None or record.get("sessionId") != session_id:
            raise RoutePlanningError(f"Route candidate {candidate_id} was not found.")
        return _route_candidate_from_record({**record, "id": candidate_id})

    async def mark_route_candidate_selected(
        self, session_id: str, candidate_id: str, selected_at: datetime
    ) -> RouteCandidate:
        existing = await self.get_route_candidate(session_id, candidate_id)
        record = await self._db.merge(
            _route_candidate_record_id(candidate_id),
            {"selectedAt": _surreal_datetime(selected_at)},
        )
        if record is None:
            raise RoutePlanningError(f"Route candidate {candidate_id} was not found.")
        logger.info(
            "Marked route candidate selected session_id=%s leg_key=%s candidate_id=%s",
            session_id,
            existing.leg_key,
            candidate_id,
        )
        return _route_candidate_from_record({**record, "id": candidate_id})

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
        logger.info(
            "Trip-planning SSE subscriber added session_id=%s subscribers=%s",
            session_id,
            len(self._subscribers.get(session_id, ())),
        )
        try:
            yield queue
        finally:
            subscribers = self._subscribers.get(session_id)
            if subscribers is not None:
                subscribers.discard(queue)
                logger.info(
                    "Trip-planning SSE subscriber removed session_id=%s subscribers=%s",
                    session_id,
                    len(subscribers),
                )
                if not subscribers:
                    self._subscribers.pop(session_id, None)

    def publish(self, session_id: str) -> None:
        subscribers = self._subscribers.get(session_id, set())
        logger.info(
            "Publishing trip-planning event wakeup session_id=%s subscribers=%s",
            session_id,
            len(subscribers),
        )
        for queue in subscribers:
            queue.put_nowait(None)


class TripPlanningService:
    def __init__(
        self,
        repository: TripPlanningRepository,
        valhalla: ValhallaRoutingClient,
        motis: MotisRoutingClient,
        event_bus: TripPlanningEventBus | None = None,
        planner: PlanningEngine | None = None,
        use_agent: bool | None = None,
    ) -> None:
        self._repository = repository
        self._event_bus = event_bus or TripPlanningEventBus()
        self._tasks: dict[str, asyncio.Task[None]] = {}
        self._pending_answers: dict[str, tuple[str, asyncio.Future[Any]]] = {}
        self._question_locks: dict[str, asyncio.Lock] = {}
        route_candidates = TripRouteCandidateService(
            repository,
            valhalla,
            motis,
            self.ask_user,
        )
        self._override_planner = planner
        self._deterministic_planner = TripPlanner(
            repository,
            route_candidates,
            self.ask_user,
        )
        self._agent_planner = (
            AgentTripPlanner(
                repository,
                self.ask_user,
                route_candidates,
            )
            if _use_agent_planner(use_agent)
            else None
        )
        if planner is not None:
            self._planner = planner
        elif self._agent_planner is not None:
            self._planner = self._agent_planner
        else:
            self._planner = self._deterministic_planner
        logger.info(
            "Trip-planning service initialized planner=%s",
            type(self._planner).__name__,
        )

    async def start_session(self, request: TripPlanningRequest) -> str:
        session_id = uuid4().hex
        await self._repository.create_session(session_id, request, _utc_now())
        task = asyncio.create_task(self._run_session(session_id))
        self._tasks[session_id] = task
        task.add_done_callback(lambda _: self._tasks.pop(session_id, None))
        logger.info(
            "Started trip-planning session session_id=%s draft_id=%s steps=%s",
            session_id,
            request.draft_id,
            len(request.steps),
        )
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
        logger.info(
            "Received trip-planning answer session_id=%s question_id=%s kind=%s",
            session_id,
            answer.question_id,
            question.kind,
        )
        await self._repository.update_session(
            session_id,
            {
                "state": "running",
                "currentQuestion": None,
                "lastMessage": "Applying your answer...",
            },
        )
        pending = self._pending_answers.get(session_id)
        if pending is not None:
            pending_question_id, future = pending
            if pending_question_id == answer.question_id and not future.done():
                future.set_result(answer.value)
        await self._emit(
            session_id,
            TripPlanningEventPayload(
                type="status",
                message="Applying your answer...",
            ),
        )

    async def ask_user(
        self,
        session_id: str,
        kind: TripPlanningQuestionKind,
        prompt: str,
        options: list[TripQuestionOption | str | dict[str, Any]] | None = None,
        unit: str | None = None,
    ) -> Any:
        lock = self._question_locks.setdefault(session_id, asyncio.Lock())
        async with lock:
            return await self._ask_user_locked(
                session_id,
                kind,
                prompt,
                options,
                unit,
            )

    async def _ask_user_locked(
        self,
        session_id: str,
        kind: TripPlanningQuestionKind,
        prompt: str,
        options: list[TripQuestionOption | str | dict[str, Any]] | None,
        unit: str | None,
    ) -> Any:
        session = await self._repository.get_session(session_id)
        if session.state in {"completed", "failed", "cancelled"}:
            raise StaleAnswerError("Session cannot ask questions in its current state")

        question = TripPlanningQuestion(
            id=uuid4().hex,
            kind=kind,
            prompt=prompt,
            unit=unit,
            options=_question_options(options),
        )
        future: asyncio.Future[Any] = asyncio.get_running_loop().create_future()
        self._pending_answers[session_id] = (question.id, future)
        logger.info(
            "Trip-planning session waiting for user session_id=%s "
            "question_id=%s kind=%s options=%s",
            session_id,
            question.id,
            kind,
            len(question.options),
        )

        await self._repository.update_session(
            session_id,
            {
                "state": "waitingForAnswer",
                "currentQuestion": _json_model(question),
                "lastMessage": prompt,
            },
        )
        await self._emit(
            session_id,
            TripPlanningEventPayload(
                type="question",
                message=prompt,
                question=question,
            ),
        )

        try:
            answer = await future
            logger.info(
                "Trip-planning user question answered session_id=%s question_id=%s",
                session_id,
                question.id,
            )
            return answer
        finally:
            pending = self._pending_answers.get(session_id)
            if pending is not None and pending[0] == question.id:
                self._pending_answers.pop(session_id, None)

    async def cancel_session(self, session_id: str) -> None:
        session = await self._repository.get_session(session_id)
        if session.state in {"completed", "failed", "cancelled"}:
            logger.info(
                "Ignoring trip-planning cancel for terminal session "
                "session_id=%s state=%s",
                session_id,
                session.state,
            )
            return

        logger.info("Cancelling trip-planning session session_id=%s", session_id)
        task = self._tasks.get(session_id)
        if task is not None:
            task.cancel()
        pending = self._pending_answers.pop(session_id, None)
        if pending is not None:
            _, future = pending
            if not future.done():
                future.cancel()
        self._question_locks.pop(session_id, None)
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
        logger.info("Opening trip-planning event stream session_id=%s", session_id)
        async with self._event_bus.subscribe(session_id) as queue:
            while True:
                events = await self._repository.list_events(
                    session_id, after_sequence=next_sequence
                )
                for event in events:
                    next_sequence = event.sequence
                    logger.info(
                        "Sending trip-planning SSE session_id=%s sequence=%s "
                        "type=%s question_id=%s message=%s",
                        session_id,
                        event.sequence,
                        event.payload.type,
                        event.payload.question.id
                        if event.payload.question is not None
                        else None,
                        event.payload.message,
                    )
                    yield _sse(event.payload)
                    logger.info(
                        "Trip-planning SSE yielded frame session_id=%s sequence=%s "
                        "type=%s",
                        session_id,
                        event.sequence,
                        event.payload.type,
                    )
                    if event.payload.type == "done":
                        logger.info(
                            "Closing trip-planning event stream session_id=%s "
                            "final_sequence=%s",
                            session_id,
                            event.sequence,
                        )
                        return

                try:
                    logger.info(
                        "Trip-planning SSE waiting for wakeup session_id=%s "
                        "after_sequence=%s",
                        session_id,
                        next_sequence,
                    )
                    await asyncio.wait_for(queue.get(), timeout=15)
                    logger.info(
                        "Trip-planning SSE wakeup received session_id=%s "
                        "after_sequence=%s",
                        session_id,
                        next_sequence,
                    )
                except TimeoutError:
                    logger.info(
                        "Sending trip-planning SSE keepalive session_id=%s "
                        "after_sequence=%s",
                        session_id,
                        next_sequence,
                    )
                    yield ": keepalive\n\n"

    async def close(self) -> None:
        for _, future in self._pending_answers.values():
            if not future.done():
                future.cancel()
        self._pending_answers.clear()
        self._question_locks.clear()
        tasks = list(self._tasks.values())
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def _run_session(self, session_id: str) -> None:
        logger.info("Running trip-planning session session_id=%s", session_id)
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

            session = await self._repository.get_session(session_id)
            planner = self._planner_for_request(session.request)
            plan = await planner.build_plan(session_id)
            logger.info(
                "Trip-planning plan built session_id=%s items=%s",
                session_id,
                len(plan.items),
            )
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
            logger.info(
                "Trip-planning session task cancelled session_id=%s", session_id
            )
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
            logger.exception("Trip-planning session %s failed", session_id)
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

    def _planner_for_request(self, request: TripPlanningRequest) -> PlanningEngine:
        if self._override_planner is not None:
            return self._override_planner
        if request.planner_mode == "deterministic":
            return self._deterministic_planner
        if self._agent_planner is None:
            logger.warning(
                "Agent planner requested but disabled; falling back to deterministic "
                "planner draft_id=%s",
                request.draft_id,
            )
            return self._deterministic_planner
        return self._agent_planner

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


class TripRouteCandidateService:
    def __init__(
        self,
        repository: TripPlanningRepository,
        valhalla: ValhallaRoutingClient,
        motis: MotisRoutingClient,
        ask_user: Any,
    ) -> None:
        self._repository = repository
        self._valhalla = valhalla
        self._motis = motis
        self._ask_user = ask_user

    async def route_between(
        self,
        session_id: str,
        leg_key: str,
        start: GeoCoordinate,
        destination: GeoCoordinate,
        modes: list[TransportMode],
        depart_at: datetime | None = None,
        arrive_by: datetime | None = None,
    ) -> list[RouteCandidate]:
        depart_at = depart_at or _utc_now()
        distance_meters = _distance_meters(start, destination)
        if distance_meters <= NEARBY_DIRECT_WALK_METERS:
            logger.info(
                "Using direct nearby walk route session_id=%s leg_key=%s "
                "from=%s to=%s distance_meters=%.1f",
                session_id,
                leg_key,
                _coord_log(start),
                _coord_log(destination),
                distance_meters,
            )
            candidate = _direct_walk_route(
                start,
                destination,
                distance_meters,
                session_id=session_id,
                leg_key=leg_key,
                depart_at=depart_at,
                arrive_by=arrive_by,
            )
            return [await self._repository.create_route_candidate(candidate)]

        candidates: list[RouteCandidate] = []
        for mode in modes:
            try:
                logger.info(
                    "Requesting route candidate session_id=%s leg_key=%s mode=%s "
                    "from=%s to=%s depart_at=%s arrive_by=%s",
                    session_id,
                    leg_key,
                    mode,
                    _coord_log(start),
                    _coord_log(destination),
                    depart_at.isoformat() if depart_at is not None else None,
                    arrive_by.isoformat() if arrive_by is not None else None,
                )
                if mode == "publicTransport":
                    mode_candidates = await self._routes_with_motis(
                        session_id,
                        leg_key,
                        start,
                        destination,
                        depart_at,
                        arrive_by,
                    )
                else:
                    mode_candidates = await self._routes_with_valhalla(
                        session_id,
                        leg_key,
                        start,
                        destination,
                        mode,
                        depart_at,
                        arrive_by,
                    )
                for candidate in mode_candidates:
                    candidates.append(
                        await self._repository.create_route_candidate(candidate)
                    )
            except (
                RoutePlanningError,
                httpx.HTTPError,
                KeyError,
                ValueError,
                TypeError,
            ) as exc:
                logger.warning(
                    "Route candidate failed session_id=%s leg_key=%s mode=%s "
                    "from=%s to=%s error=%s",
                    session_id,
                    leg_key,
                    mode,
                    _coord_log(start),
                    _coord_log(destination),
                    exc,
                )
                continue

        if not candidates:
            raise RoutePlanningError(
                "No reachable route was found for a required trip leg."
            )
        return candidates

    async def select_route(
        self,
        session_id: str,
        leg_key: str,
        start: GeoCoordinate,
        destination: GeoCoordinate,
        modes: list[TransportMode],
        depart_at: datetime,
        title: str,
        arrive_by: datetime | None = None,
    ) -> RouteCandidate:
        candidates = await self.route_between(
            session_id=session_id,
            leg_key=leg_key,
            start=start,
            destination=destination,
            modes=modes,
            depart_at=depart_at,
            arrive_by=arrive_by,
        )
        candidates = sorted(candidates, key=lambda candidate: candidate.duration_seconds)
        if len(candidates) == 1:
            return await self._repository.mark_route_candidate_selected(
                session_id,
                candidates[0].id,
                _utc_now(),
            )

        offered_candidates = candidates[:TRIP_PLANNING_OPTION_LIMIT]
        options = [
            _route_choice_option(candidate, index)
            for index, candidate in enumerate(offered_candidates, start=1)
        ]
        answer = await self._ask_user(
            session_id,
            "routeChoice",
            f"Choose a route for {title}.",
            options,
        )
        candidate_id = _route_candidate_id_from_answer(answer)
        if candidate_id not in {candidate.id for candidate in offered_candidates}:
            raise InvalidAnswerError("routeChoice answer must reference a candidate")
        return await self._repository.mark_route_candidate_selected(
            session_id,
            candidate_id,
            _utc_now(),
        )

    async def route_chain(
        self,
        session_id: str,
        points: list[GeoCoordinate],
        modes: list[TransportMode],
        start_at: datetime | None = None,
        end_by: datetime | None = None,
    ) -> list[dict[str, Any]]:
        if len(points) < 2:
            return []
        current_time = start_at or _utc_now()
        summaries: list[dict[str, Any]] = []
        for index, (start, destination) in enumerate(pairwise(points), start=1):
            selected = await self.select_route(
                session_id=session_id,
                leg_key=f"chain-{index}",
                start=start,
                destination=destination,
                modes=modes,
                depart_at=current_time,
                arrive_by=end_by if index == len(points) - 1 else None,
                title=f"leg {index}",
            )
            summaries.append(_route_candidate_summary(selected))
            current_time += timedelta(seconds=selected.duration_seconds)
        return summaries

    async def get_candidate(self, session_id: str, candidate_id: str) -> RouteCandidate:
        return await self._repository.get_route_candidate(session_id, candidate_id)

    async def _routes_with_valhalla(
        self,
        session_id: str,
        leg_key: str,
        start: GeoCoordinate,
        destination: GeoCoordinate,
        mode: TransportMode,
        depart_at: datetime | None,
        arrive_by: datetime | None,
    ) -> list[RouteCandidate]:
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
                alternates=VALHALLA_ALTERNATE_COUNT,
            )
        )
        trips = _valhalla_trips(response)
        if not trips:
            raise RoutePlanningError("Valhalla response did not contain a trip")
        return [
            _valhalla_route_candidate(
                trip=trip,
                raw_payload=raw_payload,
                session_id=session_id,
                leg_key=leg_key,
                start=start,
                destination=destination,
                mode=mode,
                depart_at=depart_at,
                arrive_by=arrive_by,
            )
            for trip, raw_payload in trips
        ]

    async def _routes_with_motis(
        self,
        session_id: str,
        leg_key: str,
        start: GeoCoordinate,
        destination: GeoCoordinate,
        depart_at: datetime,
        arrive_by: datetime | None,
    ) -> list[RouteCandidate]:
        response = await self._motis.plan(
            MotisPlanRequest(
                fromPlace=_motis_place(start),
                toPlace=_motis_place(destination),
                time=arrive_by or depart_at,
                arriveBy=arrive_by is not None,
                detailedLegs=True,
                detailedTransfers=True,
                joinInterlinedLegs=False,
                directModes=[],
                preTransitModes=["WALK"],
                postTransitModes=["WALK"],
                transitModes=["TRANSIT"],
                numItineraries=MOTIS_ITINERARY_COUNT,
                numLegAlternatives=MOTIS_LEG_ALTERNATIVE_COUNT,
                timetableView=False,
                language=["de", "en"],
            )
        )
        itineraries = response.get("itineraries")
        if not isinstance(itineraries, list) or not itineraries:
            raise RoutePlanningError("MOTIS response did not contain itineraries")
        candidates = [
            _motis_route_candidate(
                itinerary=itinerary,
                session_id=session_id,
                leg_key=leg_key,
                start=start,
                destination=destination,
                depart_at=depart_at,
                arrive_by=arrive_by,
            )
            for raw_itinerary in itineraries
            if (itinerary := _dict_value(raw_itinerary)) is not None
        ]
        if not candidates:
            raise RoutePlanningError("MOTIS itinerary was not an object")
        return candidates


def _valhalla_trips(
    response: dict[str, Any],
) -> list[tuple[dict[str, Any], dict[str, Any]]]:
    trips: list[tuple[dict[str, Any], dict[str, Any]]] = []
    trip = _dict_value(response.get("trip"))
    if trip is not None:
        trips.append((trip, response))
    alternates = response.get("alternates")
    if isinstance(alternates, list):
        for raw_alternate in alternates:
            alternate = _dict_value(raw_alternate)
            if alternate is None:
                continue
            alternate_trip = _dict_value(alternate.get("trip")) or alternate
            trips.append((alternate_trip, alternate))
    return trips


def _valhalla_route_candidate(
    *,
    trip: dict[str, Any],
    raw_payload: dict[str, Any],
    session_id: str,
    leg_key: str,
    start: GeoCoordinate,
    destination: GeoCoordinate,
    mode: TransportMode,
    depart_at: datetime | None,
    arrive_by: datetime | None,
) -> RouteCandidate:
    summary = _dict_value(trip.get("summary")) or {}
    duration = _int_value(summary.get("time")) or 0
    length_km = _float_value(summary.get("length"))
    geometry = [
        *_coordinates_from_any(trip.get("shape")),
        *_coordinates_from_valhalla_legs(trip.get("legs")),
    ]
    description = _route_description(mode, duration, length_km)
    return RouteCandidate(
        id=uuid4().hex,
        session_id=session_id,
        leg_key=leg_key,
        start=start,
        destination=destination,
        mode=mode,
        duration_seconds=duration,
        distance_meters=None if length_km is None else length_km * 1000,
        geometry=geometry,
        description=description,
        segments=[
            TripRouteSegment(
                transport_mode=mode,
                geometry=geometry,
                description=description,
            )
        ],
        provider="valhalla",
        depart_at=depart_at,
        arrive_by=arrive_by,
        raw_provider_payload=raw_payload,
        created_at=_utc_now(),
    )


def _motis_route_candidate(
    *,
    itinerary: dict[str, Any],
    session_id: str,
    leg_key: str,
    start: GeoCoordinate,
    destination: GeoCoordinate,
    depart_at: datetime,
    arrive_by: datetime | None,
) -> RouteCandidate:
    legs = itinerary.get("legs")
    duration = _int_value(itinerary.get("duration"))
    if duration is None:
        duration = _motis_legs_duration(legs)
    distance = _motis_legs_distance(legs)
    geometry = _coordinates_from_motis_legs(legs)
    segments = _segments_from_motis_legs(legs)
    description = _motis_description(legs, duration)
    return RouteCandidate(
        id=uuid4().hex,
        session_id=session_id,
        leg_key=leg_key,
        start=start,
        destination=destination,
        mode="publicTransport",
        duration_seconds=duration,
        distance_meters=distance,
        geometry=geometry,
        description=description,
        segments=segments
        or [
            TripRouteSegment(
                transport_mode="publicTransport",
                geometry=geometry,
                description=description,
            )
        ],
        provider="motis",
        depart_at=depart_at,
        arrive_by=arrive_by,
        raw_provider_payload=itinerary,
        created_at=_utc_now(),
    )


class TripPlanner:
    def __init__(
        self,
        repository: TripPlanningRepository,
        route_candidates: TripRouteCandidateService,
        ask_user: Any,
    ) -> None:
        self._repository = repository
        self._route_candidates = route_candidates
        self._ask_user = ask_user

    async def build_plan(self, session_id: str) -> TripPlan:
        session = await self._repository.get_session(session_id)
        request = session.request
        cursor = request.start_location
        current_time = _initial_time(request)
        items: list[TripPlanItem] = []
        logger.info(
            "Building deterministic trip plan session_id=%s steps=%s start=%s end=%s",
            session_id,
            len(request.steps),
            _coord_log(request.start_location),
            _coord_log(request.end_location),
        )

        for index, step in enumerate(request.steps, start=1):
            logger.info(
                "Planning step session_id=%s step_index=%s step_id=%s type=%s title=%s",
                session_id,
                index,
                step.id,
                step.type,
                step.title,
            )
            activity_locations = await self._resolve_activity_locations(
                session_id,
                step,
                cursor,
            )
            logger.info(
                "Resolved step locations session_id=%s step_index=%s count=%s",
                session_id,
                index,
                len(activity_locations),
            )
            activity_duration = _split_activity_duration(
                step.time.duration_minutes,
                len(activity_locations),
            )
            for location_index, activity_location in enumerate(
                activity_locations,
                start=1,
            ):
                item_suffix = _expanded_item_suffix(
                    index,
                    location_index,
                    len(activity_locations),
                )
                activity_title = _activity_title(
                    step,
                    activity_location,
                    len(activity_locations),
                )

                if not _same_place(cursor, activity_location):
                    route = await self._route_candidates.select_route(
                        session_id=session_id,
                        leg_key=f"step-{item_suffix}",
                        start=cursor,
                        destination=activity_location,
                        modes=request.transport_modes,
                        depart_at=current_time,
                        title=f"Travel to {activity_title}",
                    )
                    logger.info(
                        "Selected route for step session_id=%s step_index=%s "
                        "location_index=%s mode=%s duration_seconds=%s "
                        "distance_meters=%s",
                        session_id,
                        index,
                        location_index,
                        route.mode,
                        route.duration_seconds,
                        _round_optional(route.distance_meters),
                    )
                    travel_start = current_time
                    travel_end = current_time + timedelta(
                        seconds=route.duration_seconds
                    )
                    items.append(
                        TripPlanItem(
                            id=f"travel-{item_suffix}",
                            type="travel",
                            title=f"Travel to {activity_title}",
                            description=route.description,
                            reasoning="Selected from available route alternatives.",
                            transport_mode=route.mode,
                            start_time=travel_start,
                            end_time=travel_end,
                            geometry=route.geometry,
                            segments=route.segments,
                        )
                    )
                    current_time = travel_end

                activity_start = _activity_start_time(step, current_time)
                activity_end = activity_start + activity_duration
                items.append(
                    TripPlanItem(
                        id=f"activity-{item_suffix}",
                        type="activity",
                        title=activity_title,
                        description=step.details or activity_title,
                        reasoning=_activity_reasoning(step, activity_location),
                        source_draft_step_id=step.id,
                        step_type=step.type,
                        start_time=activity_start,
                        end_time=activity_end,
                        location=activity_location,
                        visual_target=_visual_target_for_activity(
                            step,
                            activity_location,
                            len(activity_locations),
                        ),
                        geometry=[],
                    )
                )
                cursor = activity_location
                current_time = activity_end

        if request.end_location is not None and not _same_place(
            cursor, request.end_location
        ):
            logger.info(
                "Planning final route session_id=%s from=%s to=%s",
                session_id,
                _coord_log(cursor),
                _coord_log(request.end_location),
            )
            route = await self._route_candidates.select_route(
                session_id=session_id,
                leg_key="final",
                start=cursor,
                destination=request.end_location,
                modes=request.transport_modes,
                depart_at=current_time,
                title="Travel to final destination",
            )
            logger.info(
                "Selected final route session_id=%s mode=%s "
                "duration_seconds=%s distance_meters=%s",
                session_id,
                route.mode,
                route.duration_seconds,
                _round_optional(route.distance_meters),
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
                    segments=route.segments,
                )
            )

        title = _plan_title(request)
        return TripPlan(
            id=f"plan-{session_id}",
            title=title,
            summary=f"{len(request.steps)} planned stops with routed travel legs.",
            items=items,
        )

    async def _resolve_activity_locations(
        self,
        session_id: str,
        step: ItineraryStepDraft,
        cursor: GeoCoordinate,
    ) -> list[GeoCoordinate]:
        constraint = step.location
        if constraint.type == "exactPoint" and constraint.point is not None:
            logger.debug(
                "Using exact step location step_id=%s location=%s",
                step.id,
                _coord_log(constraint.point),
            )
            return [_with_default_label(constraint.point, step.title)]

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
            limit=TRIP_PLANNING_OPTION_LIMIT,
        )
        if candidates:
            options = [
                _poi_choice_option(step, candidate, option_index)
                for option_index, candidate in enumerate(candidates, start=1)
            ]
            answer = await self._ask_user(
                session_id,
                "selection",
                f"Choose places for {step.title}.",
                options,
            )
            selected_ids = _selected_option_ids_from_answer(answer)
            selected = [
                candidate
                for option, candidate in zip(options, candidates, strict=True)
                if option["id"] in selected_ids
            ]
            if not selected:
                raise InvalidAnswerError("selection answers must reference an option")
            logger.info(
                "Using selected POIs for step step_id=%s candidates=%s selected=%s",
                step.id,
                len(candidates),
                len(selected),
            )
            return _greedy_order_coordinates(
                [
                    _with_default_label(candidate.coordinate, step.title)
                    for candidate in selected
                ],
                cursor,
            )
        logger.info(
            "No POI candidates found for step step_id=%s; using center=%s",
            step.id,
            _coord_log(center),
        )
        return [_with_default_label(center, step.title)]


class AgentTripPlanner:
    def __init__(
        self,
        repository: TripPlanningRepository,
        ask_user: Any,
        route_candidates: TripRouteCandidateService,
    ) -> None:
        self._repository = repository
        self._ask_user = ask_user
        self._route_candidates = route_candidates

    async def build_plan(self, session_id: str) -> TripPlan:
        from pydantic_ai_local import plan_trip

        session = await self._repository.get_session(session_id)
        request = session.request
        agent_input = _agent_input_from_request(request)
        logger.info(
            "Building agent trip plan session_id=%s steps=%s locations=%s "
            "radius_meters=%s max_stops=%s",
            session_id,
            len(request.steps),
            len(agent_input.trip_locations),
            agent_input.radius_meters,
            agent_input.max_stops,
        )
        agent_output = await plan_trip(
            agent_input,
            session_id=session_id,
            ask_user=self._ask_user,
            route_between=self._agent_route_between,
            route_chain=self._agent_route_chain,
        )
        logger.info(
            "Agent trip plan output received session_id=%s "
            "ordered_groups=%s warnings=%s",
            session_id,
            len(getattr(agent_output, "ordered_points", [])),
            len(getattr(agent_output, "warnings", []) or []),
        )
        return await _trip_plan_from_agent_output(
            session_id,
            request,
            agent_output,
            self._route_candidates,
        )

    async def _agent_route_between(
        self,
        session_id: str,
        start: GeoCoordinate,
        destination: GeoCoordinate,
        modes: list[TransportMode],
        depart_at: datetime | None = None,
        arrive_by: datetime | None = None,
        leg_key: str | None = None,
    ) -> list[dict[str, Any]]:
        candidates = await self._route_candidates.route_between(
            session_id=session_id,
            leg_key=leg_key or uuid4().hex,
            start=start,
            destination=destination,
            modes=modes,
            depart_at=depart_at,
            arrive_by=arrive_by,
        )
        return [_route_candidate_summary(candidate) for candidate in candidates]

    async def _agent_route_chain(
        self,
        session_id: str,
        points: list[GeoCoordinate],
        modes: list[TransportMode],
        start_at: datetime | None = None,
        end_by: datetime | None = None,
    ) -> list[dict[str, Any]]:
        return await self._route_candidates.route_chain(
            session_id=session_id,
            points=points,
            modes=modes,
            start_at=start_at,
            end_by=end_by,
        )


def _use_agent_planner(use_agent: bool | None) -> bool:
    if use_agent is not None:
        return use_agent
    return getenv("NO_AGENT", "").strip().lower() not in {"1", "true", "yes", "on"}


def _agent_input_from_request(request: TripPlanningRequest) -> Any:
    from pydantic_ai_local import TripLocations, TripPlanInput

    locations = []
    radii = []
    cursor = request.start_location
    for step in request.steps:
        center, radius_meters = _agent_location_center(step, cursor)
        cursor = center
        radii.append(radius_meters)
        locations.append(
            TripLocations(
                city=_agent_city_label(center, step),
                lat=center.lat,
                lon=center.lon,
                category=_agent_category(step.type),
                notes=step.details or None,
            )
        )

    return TripPlanInput(
        start_point=(request.start_location.lat, request.start_location.lon),
        end_point=(
            (request.end_location or request.start_location).lat,
            (request.end_location or request.start_location).lon,
        ),
        trip_locations=locations,
        max_stops=max(1, len(request.steps) * 6),
        radius_meters=round(max(radii, default=5000.0)),
    )


def _agent_location_center(
    step: ItineraryStepDraft, cursor: GeoCoordinate
) -> tuple[GeoCoordinate, float]:
    constraint = step.location
    if (
        constraint.type in {"exactPoint", "aroundPoint"}
        and constraint.point is not None
    ):
        return constraint.point, constraint.radius_meters or 750.0
    if constraint.type == "areaCircle" and constraint.center is not None:
        return constraint.center, constraint.radius_meters or 1000.0
    minutes = constraint.max_transport_minutes or 15
    return cursor, max(500.0, min(minutes * 80.0, 5000.0))


def _agent_city_label(center: GeoCoordinate, step: ItineraryStepDraft) -> str:
    if center.label:
        return center.label
    if step.title:
        return step.title
    return ""


def _agent_category(step_type: ItineraryStepType) -> str:
    if step_type == "shop":
        return "shop"
    if step_type in {"eat", "party"}:
        return "restaurant"
    if step_type == "sightsee":
        return "sightseeing"
    if step_type in {"walk", "meander", "transit", "exactLocation"}:
        return "other"
    return "other"


async def _trip_plan_from_agent_output(
    session_id: str,
    request: TripPlanningRequest,
    agent_output: Any,
    route_candidates: TripRouteCandidateService,
) -> TripPlan:
    current_time = _initial_time(request)
    cursor = request.start_location
    items: list[TripPlanItem] = []
    ordered_groups = getattr(agent_output, "ordered_points", [])

    for group_index, raw_group in enumerate(ordered_groups):
        step = request.steps[min(group_index, len(request.steps) - 1)]
        for point_index, raw_point in enumerate(
            _agent_group_points(raw_group), start=1
        ):
            coordinate = _agent_point_coordinate(raw_point)
            if coordinate is None:
                continue

            title = _agent_point_title(raw_point) or step.title
            activity_location = _with_default_label(coordinate, title)
            if not _same_place(cursor, activity_location):
                route = await route_candidates.select_route(
                    session_id=session_id,
                    leg_key=f"agent-{group_index + 1}-{point_index}",
                    start=cursor,
                    destination=activity_location,
                    modes=request.transport_modes,
                    depart_at=current_time,
                    title=f"Travel to {title}",
                )
                travel_start = current_time
                travel_end = current_time + timedelta(seconds=route.duration_seconds)
                items.append(
                    TripPlanItem(
                        id=f"travel-{group_index + 1}-{point_index}",
                        type="travel",
                        title=f"Travel to {title}",
                        description=route.description,
                        reasoning="Selected from stored route candidates.",
                        transport_mode=route.mode,
                        start_time=travel_start,
                        end_time=travel_end,
                        geometry=route.geometry,
                        segments=route.segments,
                    )
                )
                current_time = travel_end

            activity_start = _activity_start_time(step, current_time)
            activity_end = activity_start + timedelta(
                minutes=step.time.duration_minutes
            )
            items.append(
                TripPlanItem(
                    id=f"activity-{group_index + 1}-{point_index}",
                    type="activity",
                    title=title,
                    description=step.details or title,
                    reasoning=getattr(agent_output, "route_strategy", None),
                    source_draft_step_id=step.id,
                    step_type=step.type,
                    start_time=activity_start,
                    end_time=activity_end,
                    location=activity_location,
                    visual_target=LocationConstraint(
                        type="exactPoint",
                        point=activity_location,
                    ),
                )
            )
            cursor = activity_location
            current_time = activity_end

    if request.end_location is not None and not _same_place(
        cursor,
        request.end_location,
    ):
        route = await route_candidates.select_route(
            session_id=session_id,
            leg_key="agent-final",
            start=cursor,
            destination=request.end_location,
            modes=request.transport_modes,
            depart_at=current_time,
            title="Travel to final destination",
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
                segments=route.segments,
            )
        )

    return TripPlan(
        id=f"plan-{session_id}",
        title=_plan_title(request),
        summary=getattr(agent_output, "summary", None),
        items=items,
    )


def _agent_group_points(raw_group: Any) -> list[Any]:
    if isinstance(raw_group, list):
        return raw_group
    return [raw_group]


def _agent_point_coordinate(raw_point: Any) -> GeoCoordinate | None:
    geometry = getattr(raw_point, "geometry", None)
    coordinates = getattr(geometry, "coordinates", None)
    if (
        isinstance(coordinates, tuple | list)
        and len(coordinates) >= 2
        and isinstance(coordinates[0], int | float)
        and isinstance(coordinates[1], int | float)
    ):
        return GeoCoordinate(lat=float(coordinates[1]), lon=float(coordinates[0]))
    return None


def _agent_point_title(raw_point: Any) -> str | None:
    properties = getattr(raw_point, "properties", None)
    if properties is None:
        return None
    for key in ("name", "operator", "office"):
        value = getattr(properties, key, None)
        if isinstance(value, str) and value:
            return value
    return None


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
        if isinstance(value, list) and not value:
            raise InvalidAnswerError("selection answers must reference an option")
        if isinstance(value, list) and all(
            isinstance(item, dict)
            or (isinstance(item, str) and (not valid_ids or item in valid_ids))
            for item in value
        ):
            return
        raise InvalidAnswerError("selection answers must reference an option")


def _question_options(
    values: list[TripQuestionOption | str | dict[str, Any]] | None,
) -> list[TripQuestionOption]:
    if values is None:
        return []

    options: list[TripQuestionOption] = []
    for index, value in enumerate(values, start=1):
        if isinstance(value, TripQuestionOption):
            options.append(value)
        elif isinstance(value, str):
            options.append(TripQuestionOption(id=value, title=value))
        elif isinstance(value, dict):
            option_id = str(
                value.get("id")
                or value.get("osm_id")
                or value.get("osmId")
                or value.get("value")
                or f"option-{index}"
            )
            title = str(
                value.get("title")
                or value.get("name")
                or value.get("label")
                or option_id
            )
            description = value.get("description")
            options.append(
                TripQuestionOption(
                    id=option_id,
                    title=title,
                    description=description if isinstance(description, str) else None,
                    image_url=_str_value(
                        value.get("imageUrl") or value.get("image_url")
                    ),
                    payload=value,
                )
            )
    return options


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


def _route_candidate_record_id(candidate_id: str) -> RecordID:
    return RecordID(ROUTE_CANDIDATE_TABLE, candidate_id)


def _route_candidate_record(candidate: RouteCandidate) -> dict[str, Any]:
    return {
        "sessionId": candidate.session_id,
        "legKey": candidate.leg_key,
        "from": _json_model(candidate.start),
        "to": _json_model(candidate.destination),
        "departAt": _surreal_datetime_or_none(candidate.depart_at),
        "arriveBy": _surreal_datetime_or_none(candidate.arrive_by),
        "mode": candidate.mode,
        "durationSeconds": candidate.duration_seconds,
        "distanceMeters": candidate.distance_meters,
        "geometry": [_json_model(coordinate) for coordinate in candidate.geometry],
        "segments": [_json_model(segment) for segment in candidate.segments],
        "summary": candidate.description,
        "provider": candidate.provider,
        "rawProviderPayload": candidate.raw_provider_payload,
        "selectedAt": _surreal_datetime_or_none(candidate.selected_at),
        "createdAt": _surreal_datetime(candidate.created_at or _utc_now()),
    }


def _route_candidate_from_record(record: Any) -> RouteCandidate:
    if not isinstance(record, dict):
        raise ValueError("Expected route candidate record")
    raw_id = record.get("id")
    candidate_id = str(raw_id.id) if isinstance(raw_id, RecordID) else str(raw_id)
    return RouteCandidate(
        id=candidate_id,
        session_id=str(record.get("sessionId")),
        leg_key=str(record.get("legKey")),
        start=GeoCoordinate.model_validate(record.get("from")),
        destination=GeoCoordinate.model_validate(record.get("to")),
        mode=record.get("mode"),
        duration_seconds=_int_value(record.get("durationSeconds")) or 0,
        distance_meters=_float_value(record.get("distanceMeters")),
        geometry=[
            GeoCoordinate.model_validate(coordinate)
            for coordinate in record.get("geometry", [])
        ],
        description=_str_value(record.get("summary")) or "",
        segments=[
            TripRouteSegment.model_validate(segment)
            for segment in record.get("segments", [])
        ],
        provider=_str_value(record.get("provider")) or "unknown",
        depart_at=_datetime_value_or_none(record.get("departAt")),
        arrive_by=_datetime_value_or_none(record.get("arriveBy")),
        raw_provider_payload=_dict_value(record.get("rawProviderPayload")),
        selected_at=_datetime_value_or_none(record.get("selectedAt")),
        created_at=_datetime_value_or_none(record.get("createdAt")),
    )


def _route_choice_option(candidate: RouteCandidate, index: int) -> dict[str, Any]:
    summary = _route_candidate_summary(candidate)
    return {
        "id": candidate.id,
        "title": f"{summary['title']} option {index}",
        "description": summary["description"],
        "routeCandidateId": candidate.id,
        "mode": candidate.mode,
        "durationSeconds": candidate.duration_seconds,
        "distanceMeters": candidate.distance_meters,
        "transferCount": summary["transferCount"],
        "departAt": candidate.depart_at.isoformat()
        if candidate.depart_at is not None
        else None,
        "arriveBy": candidate.arrive_by.isoformat()
        if candidate.arrive_by is not None
        else None,
        "summary": candidate.description,
    }


def _poi_choice_option(
    step: ItineraryStepDraft,
    candidate: PoiCandidate,
    index: int,
) -> dict[str, Any]:
    coordinate = _with_default_label(candidate.coordinate, step.title)
    category = _poi_category_label(candidate)
    distance = (
        None
        if candidate.distance_meters is None
        else _distance_label(candidate.distance_meters)
    )
    description_parts = [
        part for part in (distance, category) if part is not None and part
    ]
    return {
        "id": f"poi-{index}",
        "title": coordinate.label or step.title,
        "description": " · ".join(description_parts) or None,
        "lat": coordinate.lat,
        "lon": coordinate.lon,
        "label": coordinate.label,
        "distanceMeters": candidate.distance_meters,
        "primaryFamily": candidate.primary_family,
        "primaryType": candidate.primary_type,
        "sourceDraftStepId": step.id,
    }


def _poi_category_label(candidate: PoiCandidate) -> str | None:
    values = [
        value.replace("_", " ")
        for value in (candidate.primary_type, candidate.primary_family)
        if value
    ]
    if not values:
        return None
    return " / ".join(values)


def _route_candidate_summary(candidate: RouteCandidate) -> dict[str, Any]:
    transfer_count = _route_transfer_count(candidate)
    distance = (
        ""
        if candidate.distance_meters is None
        else f", {_distance_label(candidate.distance_meters)}"
    )
    transfers = (
        ""
        if transfer_count == 0
        else f", {transfer_count} transfer{'s' if transfer_count != 1 else ''}"
    )
    return {
        "routeCandidateId": candidate.id,
        "title": _transport_mode_label(candidate.mode),
        "description": (
            f"{_minutes(candidate.duration_seconds)} min{distance}{transfers}. "
            f"{candidate.description}"
        ),
        "mode": candidate.mode,
        "durationSeconds": candidate.duration_seconds,
        "distanceMeters": candidate.distance_meters,
        "transferCount": transfer_count,
        "departAt": candidate.depart_at.isoformat()
        if candidate.depart_at is not None
        else None,
        "arriveBy": candidate.arrive_by.isoformat()
        if candidate.arrive_by is not None
        else None,
        "summary": candidate.description,
    }


def _route_transfer_count(candidate: RouteCandidate) -> int:
    transit_segments = [
        segment
        for segment in candidate.segments
        if segment.transport_mode == "publicTransport"
    ]
    return max(0, len(transit_segments) - 1)


def _route_candidate_id_from_answer(answer: Any) -> str:
    if isinstance(answer, str):
        return answer
    if isinstance(answer, dict):
        value = answer.get("routeCandidateId") or answer.get("id")
        if isinstance(value, str):
            return value
    raise InvalidAnswerError("routeChoice answer must reference a route candidate")


def _selected_option_ids_from_answer(answer: Any) -> list[str]:
    if isinstance(answer, str):
        return [answer]
    if isinstance(answer, dict):
        value = answer.get("id") or answer.get("value")
        if isinstance(value, str):
            return [value]
    if isinstance(answer, list):
        selected_ids: list[str] = []
        for item in answer:
            if isinstance(item, str):
                selected_ids.append(item)
            elif isinstance(item, dict):
                value = item.get("id") or item.get("value")
                if isinstance(value, str):
                    selected_ids.append(value)
        if selected_ids:
            return selected_ids
    raise InvalidAnswerError("selection answers must reference an option")


def _surreal_datetime(value: datetime) -> Datetime:
    value = _ensure_aware(value).astimezone(UTC)
    return Datetime(value.isoformat().replace("+00:00", "Z"))


def _surreal_datetime_or_none(value: datetime | None) -> Datetime | None:
    if value is None:
        return None
    return _surreal_datetime(value)


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
    now = _utc_now()
    if first_start is None:
        return now
    return max(now, _ensure_aware(first_start))


def _activity_start_time(step: ItineraryStepDraft, current_time: datetime) -> datetime:
    start = step.time.start_time
    if start is None and step.time.arrival_time is not None:
        start = step.time.arrival_time - timedelta(minutes=step.time.duration_minutes)
    if start is None:
        return current_time
    return max(current_time, _ensure_aware(start))


def _split_activity_duration(
    duration_minutes: int,
    activity_count: int,
) -> timedelta:
    count = max(1, activity_count)
    total_seconds = duration_minutes * 60
    return timedelta(seconds=round(total_seconds / count))


def _ensure_aware(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value


def _plan_title(request: TripPlanningRequest) -> str:
    if len(request.steps) == 1:
        return request.steps[0].title
    return f"{len(request.steps)} stop trip"


def _expanded_item_suffix(
    step_index: int,
    location_index: int,
    location_count: int,
) -> str:
    if location_count == 1:
        return str(step_index)
    return f"{step_index}-{location_index}"


def _activity_title(
    step: ItineraryStepDraft,
    coordinate: GeoCoordinate,
    location_count: int,
) -> str:
    if location_count > 1 and coordinate.label:
        return coordinate.label
    return step.title


def _activity_reasoning(
    step: ItineraryStepDraft, coordinate: GeoCoordinate
) -> str | None:
    label = coordinate.label
    if label is None:
        return "Selected from the requested location constraint."
    return f"Selected {label} for the requested {step.type} stop."


def _visual_target_for_step(step: ItineraryStepDraft) -> LocationConstraint | None:
    if step.location.type in {"exactPoint", "aroundPoint", "areaCircle"}:
        return step.location
    return None


def _visual_target_for_activity(
    step: ItineraryStepDraft,
    coordinate: GeoCoordinate,
    location_count: int,
) -> LocationConstraint | None:
    if location_count > 1 or step.location.type != "exactPoint":
        return LocationConstraint(type="exactPoint", point=coordinate)
    return _visual_target_for_step(step)


def _greedy_order_coordinates(
    coordinates: list[GeoCoordinate],
    start: GeoCoordinate,
) -> list[GeoCoordinate]:
    remaining = list(coordinates)
    ordered: list[GeoCoordinate] = []
    cursor = start
    while remaining:
        closest = min(
            remaining,
            key=lambda coordinate: _distance_meters(cursor, coordinate),
        )
        remaining.remove(closest)
        ordered.append(closest)
        cursor = closest
    return ordered


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


def _distance_meters(first: GeoCoordinate, second: GeoCoordinate) -> float:
    radius_meters = 6371000.0
    first_lat = math.radians(first.lat)
    second_lat = math.radians(second.lat)
    delta_lat = math.radians(second.lat - first.lat)
    delta_lon = math.radians(second.lon - first.lon)
    haversine = (
        math.sin(delta_lat / 2) ** 2
        + math.cos(first_lat) * math.cos(second_lat) * math.sin(delta_lon / 2) ** 2
    )
    return 2 * radius_meters * math.asin(math.sqrt(haversine))


def _coord_log(coordinate: GeoCoordinate | None) -> str | None:
    if coordinate is None:
        return None
    return f"{coordinate.lat:.5f},{coordinate.lon:.5f}"


def _round_optional(value: float | None) -> float | None:
    if value is None:
        return None
    return round(value, 1)


def _direct_walk_route(
    start: GeoCoordinate,
    destination: GeoCoordinate,
    distance_meters: float,
    session_id: str = "",
    leg_key: str = "",
    depart_at: datetime | None = None,
    arrive_by: datetime | None = None,
) -> RouteCandidate:
    duration_seconds = max(30, round(distance_meters / 1.4))
    geometry = [
        GeoCoordinate(lat=start.lat, lon=start.lon, label=start.label),
        GeoCoordinate(
            lat=destination.lat, lon=destination.lon, label=destination.label
        ),
    ]
    description = _walk_description(distance_meters, duration_seconds)
    return RouteCandidate(
        id=uuid4().hex,
        session_id=session_id,
        leg_key=leg_key,
        start=start,
        destination=destination,
        mode="walk",
        duration_seconds=duration_seconds,
        distance_meters=distance_meters,
        geometry=geometry,
        description=description,
        segments=[
            TripRouteSegment(
                transport_mode="walk",
                geometry=geometry,
                description=description,
            )
        ],
        provider="direct",
        depart_at=depart_at,
        arrive_by=arrive_by,
        created_at=_utc_now(),
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


def _walk_description(distance_meters: float, duration_seconds: int) -> str:
    minutes = _minutes(duration_seconds)
    if distance_meters < 1000:
        distance = f"{round(distance_meters)} m"
    else:
        distance = f"{distance_meters / 1000:.1f} km"
    duration = "less than 1 min" if minutes < 1 else f"about {minutes} min"
    return f"Walk {distance}, {duration}."


def _transport_mode_label(mode: TransportMode) -> str:
    if mode == "walk":
        return "Walk"
    if mode == "bike":
        return "Bike"
    if mode == "drive":
        return "Drive"
    return "Public transport"


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


def _segments_from_motis_legs(raw_legs: Any) -> list[TripRouteSegment]:
    if not isinstance(raw_legs, list):
        return []
    segments: list[TripRouteSegment] = []
    for raw_leg in raw_legs:
        leg = _dict_value(raw_leg)
        if leg is None:
            continue
        mode = _transport_mode_from_motis(_str_value(leg.get("mode")))
        segments.append(
            TripRouteSegment(
                transport_mode=mode,
                geometry=_coordinates_from_motis_geometry(leg.get("legGeometry")),
                description=_motis_leg_description(leg, mode),
                transit_details=_transit_details_from_motis_leg(leg),
            )
        )
    return segments


def _transit_details_from_motis_leg(leg: dict[str, Any]) -> TransitLegDetails:
    return TransitLegDetails(
        from_label=_place_label(leg.get("from"), "Start"),
        to_label=_place_label(leg.get("to"), "Destination"),
        route_name=_str_value(leg.get("routeName")),
        route_short_name=_str_value(leg.get("routeShortName")),
        route_long_name=_str_value(leg.get("routeLongName")),
        display_name=_str_value(leg.get("displayName")),
        vehicle_type=_vehicle_type_label(_str_value(leg.get("mode"))),
        headsign=_str_value(leg.get("headsign")),
        agency_name=_str_value(leg.get("agencyName")),
        start_time=_datetime_value_or_none(leg.get("startTime")),
        end_time=_datetime_value_or_none(leg.get("endTime")),
        scheduled_start_time=_datetime_value_or_none(leg.get("scheduledStartTime")),
        scheduled_end_time=_datetime_value_or_none(leg.get("scheduledEndTime")),
        real_time=_bool_value(leg.get("realTime")),
        cancelled=_bool_value(leg.get("cancelled")),
        intermediate_stop_labels=_intermediate_stop_labels(
            leg.get("intermediateStops")
        ),
        instructions=_step_instructions(leg.get("steps")),
    )


def _place_label(value: Any, fallback: str) -> str:
    place = _dict_value(value)
    if place is None:
        return fallback
    return _str_value(place.get("name")) or fallback


def _intermediate_stop_labels(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    labels: list[str] = []
    for raw_stop in value:
        stop = _dict_value(raw_stop)
        label = _str_value(stop.get("name")) if stop is not None else None
        if label is not None:
            labels.append(label)
    return labels


def _step_instructions(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    instructions: list[str] = []
    for raw_step in value:
        step = _dict_value(raw_step)
        instruction = _step_instruction(step)
        if instruction is not None:
            instructions.append(instruction)
    return instructions


def _step_instruction(step: dict[str, Any] | None) -> str | None:
    if step is None:
        return None
    direction = _direction_label(_str_value(step.get("relativeDirection")))
    street_name = _str_value(step.get("streetName"))
    distance = _float_value(step.get("distance"))
    distance_label = _distance_label(distance) if distance is not None else None
    if street_name is not None and distance_label is not None:
        return f"{direction} on {street_name} for {distance_label}"
    if street_name is not None:
        return f"{direction} on {street_name}"
    if distance_label is not None:
        return f"{direction} for {distance_label}"
    return direction


def _direction_label(direction: str | None) -> str:
    if direction == "DEPART":
        return "Start"
    if direction == "CONTINUE":
        return "Continue"
    if direction in {"LEFT", "SLIGHTLY_LEFT", "HARD_LEFT"}:
        return "Turn left"
    if direction in {"RIGHT", "SLIGHTLY_RIGHT", "HARD_RIGHT"}:
        return "Turn right"
    if direction == "STAIRS":
        return "Take the stairs"
    if direction == "ELEVATOR":
        return "Take the elevator"
    if direction in {"UTURN_LEFT", "UTURN_RIGHT"}:
        return "Make a U-turn"
    if direction in {"CIRCLE_CLOCKWISE", "CIRCLE_COUNTERCLOCKWISE"}:
        return "Enter the circle"
    return "Continue"


def _distance_label(distance_meters: float) -> str:
    if distance_meters >= 1000:
        return f"{distance_meters / 1000:.1f} km"
    return f"{round(distance_meters)} m"


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


def _transport_mode_from_motis(mode: str | None) -> TransportMode:
    if mode == "WALK":
        return "walk"
    if mode in {"BIKE", "RENTAL"}:
        return "bike"
    if mode in {"CAR", "CAR_PARKING", "CAR_DROPOFF"}:
        return "drive"
    return "publicTransport"


def _vehicle_type_label(mode: str | None) -> str | None:
    if mode in {"BUS", "COACH"}:
        return "Bus"
    if mode == "TRAM":
        return "Tram"
    if mode in {"SUBWAY", "METRO"}:
        return "Subway"
    if mode in {
        "RAIL",
        "HIGHSPEED_RAIL",
        "LONG_DISTANCE",
        "NIGHT_RAIL",
        "REGIONAL_FAST_RAIL",
        "REGIONAL_RAIL",
        "SUBURBAN",
    }:
        return "Train"
    if mode == "FERRY":
        return "Ferry"
    if mode == "FUNICULAR":
        return "Funicular"
    if mode in {"AERIAL_LIFT", "CABLE_CAR", "AREAL_LIFT"}:
        return "Cable car"
    if mode == "AIRPLANE":
        return "Flight"
    if mode == "TRANSIT":
        return "Transit"
    return None


def _motis_leg_description(leg: dict[str, Any], mode: TransportMode) -> str:
    name = (
        _str_value(leg.get("displayName"))
        or _str_value(leg.get("routeShortName"))
        or _str_value(leg.get("routeLongName"))
        or _transport_mode_label(mode)
    )
    duration = _int_value(leg.get("duration"))
    if duration is None:
        return name
    return f"{name}, about {_minutes(duration)} min."


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


def _bool_value(value: Any) -> bool | None:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        if value.lower() == "true":
            return True
        if value.lower() == "false":
            return False
    return None


def _datetime_value_or_none(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        with contextlib.suppress(ValueError):
            return datetime.fromisoformat(value)
    return None
