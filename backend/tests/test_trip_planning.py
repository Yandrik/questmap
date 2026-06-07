from __future__ import annotations

import asyncio
import json
from datetime import UTC, datetime
from typing import Any

import pytest

from trip_planning import (
    InvalidAnswerError,
    PoiCandidate,
    RoutePlanningError,
    SessionNotFoundError,
    StaleAnswerError,
    StoredPlanningEvent,
    TripPlanningService,
)
from trip_planning_models import (
    GeoCoordinate,
    ItineraryStepDraft,
    LocationConstraint,
    TimeConstraint,
    TripPlanningEventPayload,
    TripPlanningRequest,
    TripPlanningSessionSnapshot,
)


@pytest.mark.asyncio
async def test_trip_planning_service_emits_route_complete_final_plan() -> None:
    repository = _FakeTripPlanningRepository()
    service = TripPlanningService(
        repository,
        _FakeValhallaClient(),
        _FakeMotisClient(),
    )

    session_id = await service.start_session(
        TripPlanningRequest(
            draft_id="draft-1",
            start_location=GeoCoordinate(lat=48.4, lon=9.99, label="Start"),
            transport_modes=["walk"],
            steps=[
                ItineraryStepDraft(
                    id="step-1",
                    type="eat",
                    title="Eat",
                    details="Chinese",
                    time=TimeConstraint(duration_minutes=60),
                    location=LocationConstraint(
                        type="exactPoint",
                        point=GeoCoordinate(
                            lat=48.401,
                            lon=9.991,
                            label="Restaurant",
                        ),
                    ),
                )
            ],
        )
    )

    frames = await _collect_sse_until_done(service, session_id)
    snapshot = await service.get_session(session_id)
    await service.close()

    assert snapshot.state == "completed"
    assert snapshot.final_plan is not None
    travel = snapshot.final_plan.items[0]
    assert travel.type == "travel"
    assert travel.transport_mode == "walk"
    assert travel.geometry == [
        GeoCoordinate(lat=48.4, lon=9.99),
        GeoCoordinate(lat=48.401, lon=9.991),
    ]
    assert "event: finalPlan" in "".join(frames)
    assert frames[-1].startswith("event: done")


@pytest.mark.asyncio
async def test_trip_planning_service_fails_when_no_mode_can_route() -> None:
    repository = _FakeTripPlanningRepository()
    service = TripPlanningService(
        repository,
        _FailingValhallaClient(),
        _FakeMotisClient(),
    )

    session_id = await service.start_session(
        TripPlanningRequest(
            draft_id="draft-1",
            start_location=GeoCoordinate(lat=48.4, lon=9.99),
            transport_modes=["walk"],
            steps=[
                ItineraryStepDraft(
                    id="step-1",
                    type="sightsee",
                    title="Sightsee",
                    details="view",
                    time=TimeConstraint(duration_minutes=30),
                    location=LocationConstraint(
                        type="exactPoint",
                        point=GeoCoordinate(lat=48.42, lon=10.01),
                    ),
                )
            ],
        )
    )

    frames = await _collect_sse_until_done(service, session_id)
    snapshot = await service.get_session(session_id)
    await service.close()

    assert snapshot.state == "failed"
    assert "event: error" in "".join(frames)
    assert snapshot.final_plan is None


@pytest.mark.asyncio
async def test_answer_question_validates_current_question() -> None:
    repository = _FakeTripPlanningRepository()
    service = TripPlanningService(
        repository,
        _FakeValhallaClient(),
        _FakeMotisClient(),
    )
    request = TripPlanningRequest(
        draft_id="draft-1",
        start_location=GeoCoordinate(lat=48.4, lon=9.99),
        transport_modes=["walk"],
        steps=[
            ItineraryStepDraft(
                id="step-1",
                type="eat",
                title="Eat",
                details="Chinese",
                time=TimeConstraint(duration_minutes=60),
                location=LocationConstraint(type="wherever"),
            )
        ],
    )
    await repository.create_session("session-1", request, datetime.now(UTC))
    await repository.update_session(
        "session-1",
        {
            "state": "waitingForAnswer",
            "currentQuestion": {
                "id": "q1",
                "kind": "yesNo",
                "prompt": "Is walking okay?",
                "options": [],
            },
        },
    )

    with pytest.raises(StaleAnswerError):
        await service.answer_question(
            "session-1",
            _answer("q2", True),
        )
    with pytest.raises(InvalidAnswerError):
        await service.answer_question(
            "session-1",
            _answer("q1", "yes"),
        )

    await service.answer_question("session-1", _answer("q1", True))
    snapshot = await service.get_session("session-1")
    await service.close()

    assert snapshot.state == "running"
    assert snapshot.current_question is None
    assert repository.events["session-1"][-1].payload.type == "status"


def test_trip_planning_request_validates_time_interval() -> None:
    with pytest.raises(ValueError, match="durationMinutes"):
        TimeConstraint(
            start_time=datetime.fromisoformat("2026-06-07T12:00:00+00:00"),
            arrival_time=datetime.fromisoformat("2026-06-07T12:15:00+00:00"),
            duration_minutes=30,
        )


async def _collect_sse_until_done(
    service: TripPlanningService, session_id: str
) -> list[str]:
    frames: list[str] = []
    async with asyncio.timeout(3):
        async for frame in service.stream_events(session_id):
            frames.append(frame)
            if frame.startswith("event: done"):
                return frames
    return frames


def _answer(question_id: str, value: Any) -> Any:
    from trip_planning_models import TripPlanningAnswer

    return TripPlanningAnswer(question_id=question_id, value=value)


class _FakeTripPlanningRepository:
    def __init__(self) -> None:
        self.sessions: dict[str, dict[str, Any]] = {}
        self.events: dict[str, list[StoredPlanningEvent]] = {}

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
        }
        self.sessions[session_id] = record
        self.events[session_id] = []
        return TripPlanningSessionSnapshot.model_validate(record)

    async def get_session(self, session_id: str) -> TripPlanningSessionSnapshot:
        if session_id not in self.sessions:
            raise SessionNotFoundError(session_id)
        return TripPlanningSessionSnapshot.model_validate(self.sessions[session_id])

    async def update_session(
        self, session_id: str, updates: dict[str, Any]
    ) -> TripPlanningSessionSnapshot:
        if session_id not in self.sessions:
            raise SessionNotFoundError(session_id)
        self.sessions[session_id].update(updates)
        self.sessions[session_id]["updatedAt"] = datetime.now(UTC).isoformat()
        return TripPlanningSessionSnapshot.model_validate(self.sessions[session_id])

    async def append_event(
        self, session_id: str, payload: TripPlanningEventPayload
    ) -> StoredPlanningEvent:
        if session_id not in self.events:
            raise SessionNotFoundError(session_id)
        event = StoredPlanningEvent(
            sequence=len(self.events[session_id]),
            payload=payload,
            created_at=datetime.now(UTC),
        )
        self.events[session_id].append(event)
        return event

    async def list_events(
        self, session_id: str, after_sequence: int = -1
    ) -> list[StoredPlanningEvent]:
        if session_id not in self.events:
            raise SessionNotFoundError(session_id)
        return [
            event
            for event in self.events[session_id]
            if event.sequence > after_sequence
        ]

    async def search_pois(
        self,
        center: GeoCoordinate,
        radius_meters: float,
        category_filter: Any,
        limit: int = 5,
    ) -> list[PoiCandidate]:
        return [
            PoiCandidate(
                coordinate=GeoCoordinate(
                    lat=center.lat + 0.001,
                    lon=center.lon + 0.001,
                    label="POI",
                )
            )
        ]


class _FakeValhallaClient:
    async def route(self, route_request: Any) -> dict[str, Any]:
        locations = route_request.locations
        start = locations[0]
        destination = locations[1]
        return {
            "trip": {
                "summary": {"length": 0.2, "time": 120},
                "shape": {
                    "type": "Feature",
                    "geometry": {
                        "type": "LineString",
                        "coordinates": [
                            [start.lon, start.lat],
                            [destination.lon, destination.lat],
                        ],
                    },
                },
                "legs": [],
            }
        }


class _FailingValhallaClient:
    async def route(self, route_request: Any) -> dict[str, Any]:
        raise RoutePlanningError("routing failed")


class _FakeMotisClient:
    async def plan(self, plan_request: Any) -> dict[str, Any]:
        return {"itineraries": []}


def _json_model(model: Any) -> dict[str, Any]:
    return json.loads(model.model_dump_json(by_alias=True, exclude_none=True))
