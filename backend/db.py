from __future__ import annotations

from pathlib import Path
from typing import Any

from surrealdb import RecordID
from surrealdb.connections.async_embedded import AsyncEmbeddedSurrealConnection
from surrealdb.connections.async_http import AsyncHttpSurrealConnection
from surrealdb.connections.async_ws import AsyncWsSurrealConnection

from models import Activity, Route, RouteStep, Trip

SurrealConnection = AsyncWsSurrealConnection | AsyncHttpSurrealConnection | AsyncEmbeddedSurrealConnection

_INIT_SQL = Path(__file__).parent / "migrations" / "init.surql"


async def init_db(db: SurrealConnection) -> None:
    """Run the schema initialisation script against an already-connected client."""
    await db.query(_INIT_SQL.read_text())


def _record_id_to_str(rid: Any) -> str:
    """Extract the bare ID string from a RecordID (strips table prefix)."""
    if isinstance(rid, RecordID):
        return str(rid.id)
    return str(rid)


def dict_to_trip(d: dict) -> Trip:
    return Trip(
        id=_record_id_to_str(d["id"]) if d.get("id") is not None else None,
        start_time=d["start_time"],
        start_location=d["start_location"],
        end_time=d["end_time"],
        end_location=d["end_location"],
        activities=[
            Activity(**a) if isinstance(a, dict) else a
            for a in d.get("activities", [])
        ],
    )


def dict_to_route(d: dict) -> Route:
    return Route(
        id=_record_id_to_str(d["id"]) if d.get("id") is not None else None,
        name=d["name"],
        trip_id=d["trip_id"],
        steps=[
            RouteStep(**s) if isinstance(s, dict) else s
            for s in d.get("steps", [])
        ],
    )
