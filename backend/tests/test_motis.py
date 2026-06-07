from __future__ import annotations

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import httpx
import pytest

from motis import MotisClient, MotisPlanRequest
from main import _normalize_transit_plan_time, transit_plan


@pytest.mark.asyncio
async def test_motis_client_gets_plan_with_openapi_query_names() -> None:
    seen_request: httpx.Request | None = None

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal seen_request
        seen_request = request
        return httpx.Response(
            200,
            json={
                "requestParameters": {},
                "debugOutput": {},
                "from": {"name": "Stuttgart", "lat": 48.7758, "lon": 9.1829},
                "to": {"name": "Ulm", "lat": 48.3984, "lon": 9.9916},
                "direct": [],
                "itineraries": [],
                "previousPageCursor": "",
                "nextPageCursor": "",
            },
        )

    http_client = httpx.AsyncClient(
        base_url="http://motis.test", transport=httpx.MockTransport(handler)
    )
    client = MotisClient("http://motis.test", http_client=http_client)

    response = await client.plan(
        MotisPlanRequest(
            fromPlace="48.7758,9.1829",
            toPlace="48.3984,9.9916",
            time=datetime.fromisoformat("2026-06-06T14:00:00+02:00"),
            transitModes=["TRANSIT"],
            directModes=[],
            preTransitModes=["WALK"],
            postTransitModes=["WALK"],
            timetableView=True,
        )
    )

    await http_client.aclose()

    assert seen_request is not None
    assert seen_request.url == (
        "http://motis.test/api/v6/plan?fromPlace=48.7758%2C9.1829&"
        "toPlace=48.3984%2C9.9916&time=2026-06-06T14%3A00%3A00%2B02%3A00&"
        "transitModes=TRANSIT&directModes=&preTransitModes=WALK&"
        "postTransitModes=WALK&timetableView=true"
    )
    assert response["from"]["name"] == "Stuttgart"


@pytest.mark.asyncio
async def test_motis_client_reads_health() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url == "http://motis.test/api/v1/health"
        return httpx.Response(200, json={"status": "ok"})

    http_client = httpx.AsyncClient(
        base_url="http://motis.test", transport=httpx.MockTransport(handler)
    )
    client = MotisClient("http://motis.test", http_client=http_client)

    response = await client.health()

    await http_client.aclose()

    assert response == {"status": "ok"}


def test_transit_plan_time_uses_motis_default_now() -> None:
    missing_time = _normalize_transit_plan_time(
        MotisPlanRequest(fromPlace="48.4,9.99", toPlace="48.5,10.0")
    )
    assert missing_time.time is None

    stale = datetime.now(UTC) - timedelta(days=2)
    stale_time = _normalize_transit_plan_time(
        MotisPlanRequest(
            fromPlace="48.4,9.99",
            toPlace="48.5,10.0",
            time=stale,
        )
    )
    assert stale_time.time is None

    future = datetime.now(UTC) + timedelta(days=1)
    future_time = _normalize_transit_plan_time(
        MotisPlanRequest(
            fromPlace="48.4,9.99",
            toPlace="48.5,10.0",
            time=future,
        )
    )
    assert future_time.time is None


@pytest.mark.asyncio
async def test_transit_plan_endpoint_omits_time_for_motis_default_now() -> None:
    motis = _RecordingMotisClient()
    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(motis=motis)))
    future = datetime.now(UTC) + timedelta(days=1)

    response = await transit_plan(
        MotisPlanRequest(
            fromPlace="48.4,9.99",
            toPlace="48.5,10.0",
            time=future,
        ),
        request,
    )

    assert response["itineraries"] == []
    assert motis.last_plan_request is not None
    assert motis.last_plan_request.time is None


class _RecordingMotisClient:
    def __init__(self) -> None:
        self.last_plan_request: MotisPlanRequest | None = None

    async def plan(self, plan_request: MotisPlanRequest) -> dict[str, object]:
        self.last_plan_request = plan_request
        return {"itineraries": []}
