from __future__ import annotations

import httpx
import pytest

from valhalla import ValhallaClient, ValhallaLocation, ValhallaRouteRequest


@pytest.mark.asyncio
async def test_valhalla_client_posts_route_request() -> None:
    seen_request: httpx.Request | None = None

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal seen_request
        seen_request = request
        return httpx.Response(
            200,
            json={
                "trip": {
                    "summary": {
                        "length": 1.2,
                        "time": 840,
                    }
                }
            },
        )

    transport = httpx.MockTransport(handler)
    http_client = httpx.AsyncClient(
        base_url="http://valhalla.test", transport=transport
    )
    client = ValhallaClient("http://valhalla.test", http_client=http_client)

    response = await client.route(
        ValhallaRouteRequest(
            locations=[
                ValhallaLocation(lat=52.517, lon=13.388),
                ValhallaLocation(lat=52.529, lon=13.401),
            ],
            costing="bicycle",
            shape_format="geojson",
        )
    )

    await http_client.aclose()

    assert seen_request is not None
    assert seen_request.url == "http://valhalla.test/route"
    assert seen_request.read() == (
        b'{"locations":[{"lat":52.517,"lon":13.388,"type":"break"},'
        b'{"lat":52.529,"lon":13.401,"type":"break"}],"costing":"bicycle",'
        b'"shape_format":"geojson","units":"kilometers"}'
    )
    assert response["trip"]["summary"]["time"] == 840


@pytest.mark.asyncio
async def test_valhalla_client_reads_status() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url == "http://valhalla.test/status"
        return httpx.Response(200, json={"version": "3.x", "tileset_last_modified": 1})

    http_client = httpx.AsyncClient(
        base_url="http://valhalla.test", transport=httpx.MockTransport(handler)
    )
    client = ValhallaClient("http://valhalla.test", http_client=http_client)

    response = await client.status()

    await http_client.aclose()

    assert response == {"version": "3.x", "tileset_last_modified": 1}


def test_route_request_validates_coordinates() -> None:
    with pytest.raises(ValueError, match="less than or equal to 90"):
        ValhallaRouteRequest(
            locations=[
                ValhallaLocation(lat=91, lon=13.388),
                ValhallaLocation(lat=52.529, lon=13.401),
            ]
        )
