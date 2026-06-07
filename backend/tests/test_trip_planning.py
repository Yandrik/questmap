from __future__ import annotations

import asyncio
import json
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest

from trip_planning import (
    AgentTripPlanner,
    InvalidAnswerError,
    PoiCandidate,
    RouteCandidate,
    RoutePlanningError,
    SessionNotFoundError,
    StaleAnswerError,
    StoredPlanningEvent,
    TripPlanner,
    TripPlanningService,
    TripRouteCandidateService,
    _route_candidate_record,
)
from trip_planning_models import (
    GeoCoordinate,
    ItineraryStepDraft,
    LocationConstraint,
    TimeConstraint,
    TripPlanningEventPayload,
    TripPlanningRequest,
    TripPlanningSessionSnapshot,
    TripRouteSegment,
)


@pytest.mark.asyncio
async def test_trip_planning_service_emits_route_complete_final_plan() -> None:
    repository = _FakeTripPlanningRepository()
    service = TripPlanningService(
        repository,
        _FakeValhallaClient(),
        _FakeMotisClient(),
        use_agent=False,
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
    assert len(travel.segments) == 1
    assert travel.segments[0].transport_mode == "walk"
    activity = snapshot.final_plan.items[1]
    assert activity.visual_target is not None
    assert activity.visual_target.type == "exactPoint"
    assert "event: finalPlan" in "".join(frames)
    assert frames[-1].startswith("event: done")


@pytest.mark.asyncio
async def test_trip_planning_service_preserves_activity_visual_targets() -> None:
    repository = _FakeTripPlanningRepository()
    service = TripPlanningService(
        repository,
        _FakeValhallaClient(),
        _FakeMotisClient(),
        use_agent=False,
    )

    session_id = await service.start_session(
        TripPlanningRequest(
            draft_id="draft-1",
            start_location=GeoCoordinate(lat=48.4, lon=9.99, label="Start"),
            transport_modes=["walk"],
            steps=[
                ItineraryStepDraft(
                    id="step-1",
                    type="shop",
                    title="Shop",
                    details="books",
                    time=TimeConstraint(duration_minutes=30),
                    location=LocationConstraint(
                        type="aroundPoint",
                        point=GeoCoordinate(lat=48.401, lon=9.991),
                    ),
                ),
                ItineraryStepDraft(
                    id="step-2",
                    type="sightsee",
                    title="Sightsee",
                    details="views",
                    time=TimeConstraint(duration_minutes=30),
                    location=LocationConstraint(
                        type="areaCircle",
                        center=GeoCoordinate(lat=48.402, lon=9.992),
                        radius_meters=800,
                    ),
                ),
            ],
        )
    )

    await _collect_sse_until_done(service, session_id)
    snapshot = await service.get_session(session_id)
    await service.close()

    assert snapshot.final_plan is not None
    activities = [item for item in snapshot.final_plan.items if item.type == "activity"]
    assert [item.visual_target.type for item in activities if item.visual_target] == [
        "aroundPoint",
        "areaCircle",
    ]
    assert activities[1].visual_target is not None
    assert activities[1].visual_target.radius_meters == 800


@pytest.mark.asyncio
async def test_trip_planning_service_preserves_motis_segment_modes() -> None:
    repository = _FakeTripPlanningRepository()
    service = TripPlanningService(
        repository,
        _FakeValhallaClient(),
        _SegmentedMotisClient(),
        use_agent=False,
    )

    session_id = await service.start_session(
        TripPlanningRequest(
            draft_id="draft-1",
            start_location=GeoCoordinate(lat=48.4, lon=9.99, label="Start"),
            transport_modes=["publicTransport"],
            steps=[
                ItineraryStepDraft(
                    id="step-1",
                    type="eat",
                    title="Eat",
                    details="lunch",
                    time=TimeConstraint(duration_minutes=45),
                    location=LocationConstraint(
                        type="exactPoint",
                        point=GeoCoordinate(lat=48.401, lon=9.991),
                    ),
                )
            ],
        )
    )

    await _collect_sse_until_done(service, session_id)
    snapshot = await service.get_session(session_id)
    await service.close()

    assert snapshot.final_plan is not None
    travel = snapshot.final_plan.items[0]
    assert travel.type == "travel"
    assert travel.transport_mode == "publicTransport"
    assert [segment.transport_mode for segment in travel.segments] == [
        "walk",
        "publicTransport",
    ]
    walk_details = travel.segments[0].transit_details
    assert walk_details is not None
    assert walk_details.to_label == "Stop A"
    assert walk_details.instructions == ["Turn right on Main Street for 120 m"]
    bus_details = travel.segments[1].transit_details
    assert bus_details is not None
    assert bus_details.vehicle_type == "Bus"
    assert bus_details.route_short_name == "7"
    assert bus_details.headsign == "Downtown"
    assert bus_details.agency_name == "Transit Agency"
    assert bus_details.start_time == datetime.fromisoformat("2026-06-07T10:05:00+00:00")
    assert bus_details.real_time is True
    assert bus_details.cancelled is False
    assert bus_details.intermediate_stop_labels == ["Middle A", "Middle B"]


@pytest.mark.asyncio
async def test_trip_planning_service_clamps_stale_start_time_for_motis() -> None:
    repository = _FakeTripPlanningRepository()
    motis = _RecordingMotisClient()
    service = TripPlanningService(
        repository,
        _FakeValhallaClient(),
        motis,
        use_agent=False,
    )
    stale_start = datetime.now(UTC) - timedelta(days=2)

    session_id = await service.start_session(
        TripPlanningRequest(
            draft_id="draft-1",
            start_location=GeoCoordinate(lat=48.4, lon=9.99, label="Start"),
            transport_modes=["publicTransport"],
            steps=[
                ItineraryStepDraft(
                    id="step-1",
                    type="eat",
                    title="Eat",
                    details="lunch",
                    time=TimeConstraint(start_time=stale_start, duration_minutes=45),
                    location=LocationConstraint(
                        type="exactPoint",
                        point=GeoCoordinate(lat=48.401, lon=9.991),
                    ),
                )
            ],
        )
    )

    await _collect_sse_until_done(service, session_id)
    await service.close()

    assert motis.last_plan_request is not None
    assert motis.last_plan_request.time is not None
    assert motis.last_plan_request.time > stale_start


@pytest.mark.asyncio
async def test_trip_planning_service_asks_route_choice() -> None:
    repository = _FakeTripPlanningRepository()
    service = TripPlanningService(
        repository,
        _FakeValhallaClient(),
        _SegmentedMotisClient(),
        use_agent=False,
    )

    session_id = await service.start_session(
        TripPlanningRequest(
            draft_id="draft-1",
            start_location=GeoCoordinate(lat=48.4, lon=9.99, label="Start"),
            transport_modes=["walk", "publicTransport"],
            steps=[
                ItineraryStepDraft(
                    id="step-1",
                    type="eat",
                    title="Eat",
                    details="lunch",
                    time=TimeConstraint(duration_minutes=45),
                    location=LocationConstraint(
                        type="exactPoint",
                        point=GeoCoordinate(lat=48.401, lon=9.991),
                    ),
                )
            ],
        )
    )

    frame = await _collect_sse_until_question(service, session_id)
    snapshot = await service.get_session(session_id)
    assert "event: question" in frame
    assert snapshot.current_question is not None
    assert snapshot.current_question.kind == "routeChoice"
    assert len(snapshot.current_question.options) == 2
    public_transport = next(
        option
        for option in snapshot.current_question.options
        if option.payload is not None and option.payload["mode"] == "publicTransport"
    )

    await service.answer_question(
        session_id,
        _answer(snapshot.current_question.id, public_transport.id),
    )
    await _collect_sse_until_done(service, session_id)
    snapshot = await service.get_session(session_id)
    await service.close()

    assert snapshot.state == "completed"
    assert snapshot.final_plan is not None
    travel = snapshot.final_plan.items[0]
    assert travel.type == "travel"
    assert travel.transport_mode == "publicTransport"
    assert repository.route_candidates[public_transport.id].selected_at is not None


@pytest.mark.asyncio
async def test_trip_planning_service_auto_selects_single_route() -> None:
    repository = _FakeTripPlanningRepository()
    service = TripPlanningService(
        repository,
        _FakeValhallaClient(),
        _FakeMotisClient(),
        use_agent=False,
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
                    details="lunch",
                    time=TimeConstraint(duration_minutes=45),
                    location=LocationConstraint(
                        type="exactPoint",
                        point=GeoCoordinate(lat=48.401, lon=9.991),
                    ),
                )
            ],
        )
    )

    await _collect_sse_until_done(service, session_id)
    await service.close()

    assert len(repository.route_candidates) == 1
    candidate = next(iter(repository.route_candidates.values()))
    assert candidate.selected_at is not None
    assert [event.payload.type for event in repository.events[session_id]] == [
        "status",
        "finalPlan",
        "done",
    ]


@pytest.mark.asyncio
async def test_trip_planning_service_fails_when_no_mode_can_route() -> None:
    repository = _FakeTripPlanningRepository()
    service = TripPlanningService(
        repository,
        _FailingValhallaClient(),
        _FakeMotisClient(),
        use_agent=False,
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
async def test_trip_planning_service_direct_walks_nearby_unroutable_legs() -> None:
    repository = _FakeTripPlanningRepository()
    service = TripPlanningService(
        repository,
        _FailingValhallaClient(),
        _FakeMotisClient(),
        use_agent=False,
    )

    session_id = await service.start_session(
        TripPlanningRequest(
            draft_id="draft-1",
            start_location=GeoCoordinate(lat=48.4, lon=9.99, label="Start"),
            transport_modes=["publicTransport"],
            steps=[
                ItineraryStepDraft(
                    id="step-1",
                    type="eat",
                    title="Eat",
                    details="nearby",
                    time=TimeConstraint(duration_minutes=30),
                    location=LocationConstraint(
                        type="exactPoint",
                        point=GeoCoordinate(lat=48.40005, lon=9.99005),
                    ),
                )
            ],
        )
    )

    await _collect_sse_until_done(service, session_id)
    snapshot = await service.get_session(session_id)
    await service.close()

    assert snapshot.state == "completed"
    assert snapshot.final_plan is not None
    travel = snapshot.final_plan.items[0]
    assert travel.type == "travel"
    assert travel.transport_mode == "walk"
    assert travel.segments[0].transport_mode == "walk"


@pytest.mark.asyncio
async def test_trip_planning_service_does_not_direct_walk_local_unroutable_legs() -> (
    None
):
    repository = _FakeTripPlanningRepository()
    service = TripPlanningService(
        repository,
        _FailingValhallaClient(),
        _FakeMotisClient(),
        use_agent=False,
    )

    session_id = await service.start_session(
        TripPlanningRequest(
            draft_id="draft-1",
            start_location=GeoCoordinate(lat=48.4, lon=9.99, label="Start"),
            transport_modes=["walk", "publicTransport"],
            steps=[
                ItineraryStepDraft(
                    id="step-1",
                    type="sightsee",
                    title="Sightsee",
                    details="nearby",
                    time=TimeConstraint(duration_minutes=30),
                    location=LocationConstraint(
                        type="exactPoint",
                        point=GeoCoordinate(lat=48.4035, lon=9.9935),
                    ),
                )
            ],
        )
    )

    await _collect_sse_until_done(service, session_id)
    snapshot = await service.get_session(session_id)
    await service.close()

    assert snapshot.state == "failed"
    assert snapshot.final_plan is None
    assert (
        snapshot.last_message == "No reachable route was found for a required trip leg."
    )


@pytest.mark.asyncio
async def test_answer_question_validates_current_question() -> None:
    repository = _FakeTripPlanningRepository()
    service = TripPlanningService(
        repository,
        _FakeValhallaClient(),
        _FakeMotisClient(),
        use_agent=False,
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


@pytest.mark.asyncio
async def test_trip_planning_service_uses_agent_unless_no_agent_is_true(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = _FakeTripPlanningRepository()
    request = TripPlanningRequest(
        draft_id="draft-1",
        start_location=GeoCoordinate(lat=48.4, lon=9.99),
        transport_modes=["walk"],
        steps=[
            ItineraryStepDraft(
                id="step-1",
                type="eat",
                title="Eat",
                details="lunch",
                time=TimeConstraint(duration_minutes=30),
                location=LocationConstraint(type="wherever"),
            )
        ],
    )
    monkeypatch.delenv("NO_AGENT", raising=False)

    service = TripPlanningService(
        repository,
        _FakeValhallaClient(),
        _FakeMotisClient(),
    )
    assert isinstance(service._planner, AgentTripPlanner)
    assert isinstance(service._planner_for_request(request), AgentTripPlanner)
    assert isinstance(
        service._planner_for_request(
            request.model_copy(update={"planner_mode": "deterministic"})
        ),
        TripPlanner,
    )
    await service.close()

    monkeypatch.setenv("NO_AGENT", "true")
    service = TripPlanningService(
        repository,
        _FakeValhallaClient(),
        _FakeMotisClient(),
    )
    assert isinstance(service._planner, TripPlanner)
    assert isinstance(service._planner_for_request(request), TripPlanner)
    await service.close()


@pytest.mark.asyncio
async def test_agent_trip_planner_converts_agent_output_to_trip_plan(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import pydantic_ai_local
    from pydantic_ai_local import (
        LocationGeometry,
        LocationProperties,
        LocationsObject,
        TripPlanOutput,
    )

    repository = _FakeTripPlanningRepository()
    request = TripPlanningRequest(
        draft_id="draft-1",
        start_location=GeoCoordinate(lat=48.4, lon=9.99),
        transport_modes=["walk"],
        steps=[
            ItineraryStepDraft(
                id="step-1",
                type="eat",
                title="Eat",
                details="vegan noodles",
                time=TimeConstraint(duration_minutes=45),
                location=LocationConstraint(
                    type="areaCircle",
                    center=GeoCoordinate(lat=48.401, lon=9.991, label="Ulm"),
                    radius_meters=900,
                ),
            )
        ],
    )
    await repository.create_session("session-1", request, datetime.now(UTC))

    async def fake_plan_trip(
        inp: Any,
        session_id: str | None = None,
        ask_user: Any = None,
        route_between: Any = None,
        route_chain: Any = None,
    ) -> TripPlanOutput:
        assert session_id == "session-1"
        assert ask_user is not None
        assert route_between is not None
        assert route_chain is not None
        assert inp.trip_locations[0].city == "Ulm"
        assert inp.trip_locations[0].category == "restaurant"
        return TripPlanOutput(
            summary="Agent-picked restaurant.",
            start_point=(48.4, 9.99),
            end_point=(48.4, 9.99),
            ordered_points=[
                LocationsObject(
                    type="Feature",
                    geometry=LocationGeometry(
                        type="Point",
                        coordinates=(9.992, 48.402),
                    ),
                    properties=LocationProperties(name="Rice House"),
                )
            ],
            route_strategy="Selected from user preferences.",
        )

    monkeypatch.setattr(pydantic_ai_local, "plan_trip", fake_plan_trip)
    planner = AgentTripPlanner(
        repository,
        lambda *args: None,
        TripRouteCandidateService(
            repository,
            _FakeValhallaClient(),
            _FakeMotisClient(),
            lambda *args: None,
        ),
    )

    plan = await planner.build_plan("session-1")

    assert plan.summary == "Agent-picked restaurant."
    assert plan.items[0].type == "travel"
    assert plan.items[0].geometry
    assert plan.items[1].title == "Rice House"
    assert plan.items[1].location == GeoCoordinate(
        lat=48.402,
        lon=9.992,
        label="Rice House",
    )
    assert plan.items[1].visual_target is not None
    assert plan.items[1].visual_target.type == "exactPoint"


def test_trip_planning_request_serializes_planner_mode() -> None:
    request = TripPlanningRequest(
        draft_id="draft-1",
        planner_mode="deterministic",
        start_location=GeoCoordinate(lat=48.4, lon=9.99),
        transport_modes=["walk"],
        steps=[
            ItineraryStepDraft(
                id="step-1",
                type="eat",
                title="Eat",
                details="lunch",
                time=TimeConstraint(duration_minutes=30),
                location=LocationConstraint(type="wherever"),
            )
        ],
    )

    assert request.model_dump(by_alias=True)["plannerMode"] == "deterministic"
    assert (
        TripPlanningRequest.model_validate(
            {
                "draftId": "draft-1",
                "plannerMode": "agent",
                "startLocation": {"lat": 48.4, "lon": 9.99},
                "transportModes": ["walk"],
                "steps": [
                    {
                        "id": "step-1",
                        "type": "eat",
                        "title": "Eat",
                        "time": {"durationMinutes": 30},
                        "location": {"type": "wherever"},
                    }
                ],
            }
        ).planner_mode
        == "agent"
    )


@pytest.mark.asyncio
async def test_ask_user_emits_question_and_waits_for_answer() -> None:
    repository = _FakeTripPlanningRepository()
    service = TripPlanningService(
        repository,
        _FakeValhallaClient(),
        _FakeMotisClient(),
        use_agent=False,
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

    ask_task = asyncio.create_task(
        service.ask_user(
            "session-1",
            "selection",
            "Choose a restaurant",
            [
                {"osm_id": 123, "name": "Rice House", "distance_m": 45},
                "fallback",
            ],
        )
    )

    question_frame = await _collect_sse_until_question(service, "session-1")
    snapshot = await service.get_session("session-1")
    assert snapshot.state == "waitingForAnswer"
    assert snapshot.current_question is not None
    assert snapshot.current_question.prompt == "Choose a restaurant"
    assert snapshot.current_question.options[0].id == "123"
    assert snapshot.current_question.options[0].title == "Rice House"
    assert snapshot.current_question.options[0].payload == {
        "osm_id": 123,
        "name": "Rice House",
        "distance_m": 45,
    }
    assert "event: question" in question_frame

    await service.answer_question(
        "session-1",
        _answer(snapshot.current_question.id, ["123", "fallback"]),
    )
    answer = await asyncio.wait_for(ask_task, timeout=1)
    await service.close()

    assert answer == ["123", "fallback"]


@pytest.mark.asyncio
async def test_ask_user_serializes_concurrent_questions() -> None:
    repository = _FakeTripPlanningRepository()
    service = TripPlanningService(
        repository,
        _FakeValhallaClient(),
        _FakeMotisClient(),
        use_agent=False,
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

    first_task = asyncio.create_task(
        service.ask_user("session-1", "text", "First question")
    )
    second_task = asyncio.create_task(
        service.ask_user("session-1", "text", "Second question")
    )

    first_question = await _wait_for_current_question(service, "session-1")
    assert first_question.prompt == "First question"
    await service.answer_question(
        "session-1",
        _answer(first_question.id, "first answer"),
    )

    second_question = await _wait_for_current_question(
        service,
        "session-1",
        previous_question_id=first_question.id,
    )
    assert second_question.prompt == "Second question"
    await service.answer_question(
        "session-1",
        _answer(second_question.id, "second answer"),
    )

    assert await asyncio.wait_for(first_task, timeout=1) == "first answer"
    assert await asyncio.wait_for(second_task, timeout=1) == "second answer"
    question_events = [
        event
        for event in repository.events["session-1"]
        if event.payload.type == "question"
    ]
    await service.close()

    assert [event.payload.question.prompt for event in question_events] == [
        "First question",
        "Second question",
    ]


def test_trip_planning_request_validates_time_interval() -> None:
    with pytest.raises(ValueError, match="durationMinutes"):
        TimeConstraint(
            start_time=datetime.fromisoformat("2026-06-07T12:00:00+00:00"),
            arrival_time=datetime.fromisoformat("2026-06-07T12:15:00+00:00"),
            duration_minutes=30,
        )


def test_route_candidate_record_uses_surreal_datetimes() -> None:
    from surrealdb import Datetime

    candidate = RouteCandidate(
        id="candidate-1",
        session_id="session-1",
        leg_key="leg-1",
        start=GeoCoordinate(lat=48.4, lon=9.99),
        destination=GeoCoordinate(lat=48.401, lon=9.991),
        mode="walk",
        duration_seconds=120,
        distance_meters=200,
        geometry=[],
        description="Walk 200 m.",
        segments=[
            TripRouteSegment(
                transport_mode="walk",
                geometry=[],
                description="Walk 200 m.",
            )
        ],
        provider="valhalla",
        depart_at=datetime.fromisoformat("2026-06-07T12:00:00+02:00"),
        selected_at=datetime.fromisoformat("2026-06-07T10:01:00+00:00"),
        created_at=datetime.fromisoformat("2026-06-07T10:00:00+00:00"),
    )

    record = _route_candidate_record(candidate)

    assert isinstance(record["departAt"], Datetime)
    assert record["departAt"].dt == "2026-06-07T10:00:00Z"
    assert isinstance(record["selectedAt"], Datetime)
    assert record["selectedAt"].dt == "2026-06-07T10:01:00Z"
    assert isinstance(record["createdAt"], Datetime)
    assert record["createdAt"].dt == "2026-06-07T10:00:00Z"


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


async def _collect_sse_until_question(
    service: TripPlanningService, session_id: str
) -> str:
    async with asyncio.timeout(3):
        async for frame in service.stream_events(session_id):
            if frame.startswith("event: question"):
                return frame
    raise AssertionError("question event was not emitted")


async def _wait_for_current_question(
    service: TripPlanningService,
    session_id: str,
    previous_question_id: str | None = None,
) -> Any:
    async with asyncio.timeout(3):
        while True:
            snapshot = await service.get_session(session_id)
            question = snapshot.current_question
            if question is not None and question.id != previous_question_id:
                return question
            await asyncio.sleep(0)


def _answer(question_id: str, value: Any) -> Any:
    from trip_planning_models import TripPlanningAnswer

    return TripPlanningAnswer(question_id=question_id, value=value)


class _FakeTripPlanningRepository:
    def __init__(self) -> None:
        self.sessions: dict[str, dict[str, Any]] = {}
        self.events: dict[str, list[StoredPlanningEvent]] = {}
        self.route_candidates: dict[str, RouteCandidate] = {}

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

    async def create_route_candidate(self, candidate: RouteCandidate) -> RouteCandidate:
        self.route_candidates[candidate.id] = candidate
        return candidate

    async def list_route_candidates(
        self, session_id: str, leg_key: str | None = None
    ) -> list[RouteCandidate]:
        return [
            candidate
            for candidate in self.route_candidates.values()
            if candidate.session_id == session_id
            and (leg_key is None or candidate.leg_key == leg_key)
        ]

    async def get_route_candidate(
        self, session_id: str, candidate_id: str
    ) -> RouteCandidate:
        candidate = self.route_candidates.get(candidate_id)
        if candidate is None or candidate.session_id != session_id:
            raise RoutePlanningError("Route candidate was not found.")
        return candidate

    async def mark_route_candidate_selected(
        self, session_id: str, candidate_id: str, selected_at: datetime
    ) -> RouteCandidate:
        candidate = await self.get_route_candidate(session_id, candidate_id)
        selected = candidate.__class__(
            **{
                **candidate.__dict__,
                "selected_at": selected_at,
            }
        )
        self.route_candidates[candidate_id] = selected
        return selected


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


class _SegmentedMotisClient:
    async def plan(self, plan_request: Any) -> dict[str, Any]:
        return {
            "itineraries": [
                {
                    "duration": 720,
                    "legs": [
                        {
                            "mode": "WALK",
                            "from": {"name": "Here"},
                            "to": {"name": "Stop A"},
                            "duration": 120,
                            "distance": 180,
                            "steps": [
                                {
                                    "relativeDirection": "RIGHT",
                                    "streetName": "Main Street",
                                    "distance": 120,
                                }
                            ],
                        },
                        {
                            "mode": "BUS",
                            "from": {"name": "Stop A"},
                            "to": {"name": "Stop B"},
                            "duration": 600,
                            "distance": 2200,
                            "displayName": "7",
                            "routeShortName": "7",
                            "routeLongName": "City Bus 7",
                            "headsign": "Downtown",
                            "agencyName": "Transit Agency",
                            "startTime": "2026-06-07T10:05:00+00:00",
                            "endTime": "2026-06-07T10:15:00+00:00",
                            "scheduledStartTime": "2026-06-07T10:03:00+00:00",
                            "scheduledEndTime": "2026-06-07T10:13:00+00:00",
                            "realTime": True,
                            "cancelled": False,
                            "intermediateStops": [
                                {"name": "Middle A"},
                                {"name": "Middle B"},
                            ],
                        },
                    ],
                }
            ]
        }


class _RecordingMotisClient(_SegmentedMotisClient):
    def __init__(self) -> None:
        self.last_plan_request: Any | None = None

    async def plan(self, plan_request: Any) -> dict[str, Any]:
        self.last_plan_request = plan_request
        return await super().plan(plan_request)


def _json_model(model: Any) -> dict[str, Any]:
    return json.loads(model.model_dump_json(by_alias=True, exclude_none=True))
