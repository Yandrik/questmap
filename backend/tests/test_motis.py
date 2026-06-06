from __future__ import annotations

from datetime import datetime

import httpx
import pytest

from motis import MotisClient, MotisPlanRequest


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
