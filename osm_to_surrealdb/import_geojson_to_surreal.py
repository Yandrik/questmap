#!/usr/bin/env python3
"""
Import stuff like /tmp/tuebingen-objects.geojson into the SurrealDB osm_object table.

The target table is expected to be SCHEMAFULL with a FLEXIBLE `tags` object.
Records are written with deterministic ids like `osm_object:node_2104976`.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any, Iterator

from surrealdb import RecordID, Surreal
from surrealdb.data.types.geometry import GeometryPoint


CLASSIFICATION_KEYS = [
    "amenity",
    "shop",
    "tourism",
    "historic",
    "leisure",
    "natural",
    "man_made",
    "public_transport",
    "railway",
    "highway",
    "building",
    "barrier",
    "waterway",
    "landuse",
    "craft",
    "office",
    "emergency",
    "healthcare",
    "sport",
    "power",
    "aeroway",
    "aerialway",
    "military",
    "place",
    "boundary",
]

STABLE_TAG_FIELDS = [
    "name",
    "operator",
    "ref",
    "brand",
    "website",
    "phone",
    "email",
    "opening_hours",
    "access",
    "wheelchair",
    "fee",
]

ADDRESS_FIELD_MAP = {
    "addr:country": "country",
    "addr:postcode": "postcode",
    "addr:city": "city",
    "addr:street": "street",
    "addr:housenumber": "housenumber",
    "addr:suburb": "suburb",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import a point-only OSM GeoJSON file into SurrealDB."
    )
    parser.add_argument(
        "--url",
        default="http://127.0.0.1:8000",
        help="SurrealDB base URL, for example http://127.0.0.1:8000.",
    )
    parser.add_argument(
        "--namespace", "--ns", default="main", help="SurrealDB namespace."
    )
    parser.add_argument(
        "--database", "--db", default="main", help="SurrealDB database."
    )
    parser.add_argument("--user", default="root", help="SurrealDB username.")
    parser.add_argument("--password", default="root", help="SurrealDB password.")
    parser.add_argument(
        "--token",
        help="JWT token. If set, this is used instead of username/password signin.",
    )
    parser.add_argument(
        "--no-auth",
        action="store_true",
        help="Do not authenticate. Useful for local embedded mem:// or file:// imports.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=500,
        help="Progress reporting interval.",
    )
    parser.add_argument(
        "--replace",
        action="store_true",
        help="Upsert each deterministic record id instead of strict create.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        help="Import only the first N features, useful for testing.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the first transformed record and exit without importing.",
    )
    parser.add_argument(
        "geojson",
        nargs="?",
        default="/tmp/tuebingen-objects.geojson",
        help="Path to the GeoJSON FeatureCollection.",
    )
    return parser.parse_args()


def first_classification(props: dict[str, Any]) -> tuple[str | None, str | None]:
    for key in CLASSIFICATION_KEYS:
        value = props.get(key)
        if value is not None:
            return key, str(value)
    return None, None


def record_id(osm_type: str, osm_id: int) -> RecordID:
    return RecordID("osm_object", f"{osm_type}_{osm_id}")


def transform_feature(feature: dict[str, Any]) -> tuple[RecordID, dict[str, Any]]:
    geometry = feature.get("geometry") or {}
    props = feature.get("properties") or {}

    if geometry.get("type") != "Point":
        raise ValueError(
            f"Only Point geometries are supported, got {geometry.get('type')!r}"
        )

    coords = geometry.get("coordinates")
    if not isinstance(coords, list) or len(coords) < 2:
        raise ValueError(f"Invalid point coordinates: {coords!r}")

    lon = float(coords[0])
    lat = float(coords[1])

    osm_type = str(props["osm_type"])
    osm_id = int(props["osm_id"])
    primary_family, primary_type = first_classification(props)

    row: dict[str, Any] = {
        "osm_type": osm_type,
        "osm_id": osm_id,
        "location": GeometryPoint(lon, lat),
        "lon": lon,
        "lat": lat,
        "primary_family": primary_family,
        "primary_type": primary_type,
        "address": {
            target: props.get(source)
            for source, target in ADDRESS_FIELD_MAP.items()
            if props.get(source) is not None
        },
        "tags": props,
    }

    for field in STABLE_TAG_FIELDS:
        row[field] = props.get(field)

    return record_id(osm_type, osm_id), row


def to_jsonable(value: Any) -> Any:
    if isinstance(value, GeometryPoint):
        return {
            "type": "Point",
            "coordinates": [value.longitude, value.latitude],
        }
    if isinstance(value, RecordID):
        return str(value)
    if isinstance(value, dict):
        return {key: to_jsonable(item) for key, item in value.items()}
    if isinstance(value, list):
        return [to_jsonable(item) for item in value]
    return value


def iter_transformed(
    path: Path, limit: int | None
) -> Iterator[tuple[RecordID, dict[str, Any]]]:
    with path.open("r", encoding="utf-8") as file:
        data = json.load(file)

    if data.get("type") != "FeatureCollection":
        raise ValueError(f"Expected FeatureCollection, got {data.get('type')!r}")

    features = data.get("features")
    if not isinstance(features, list):
        raise ValueError("Expected `features` to be a list")

    count = 0
    for feature in features:
        if limit is not None and count >= limit:
            break
        yield transform_feature(feature)
        count += 1


def connect(args: argparse.Namespace) -> Any:
    db = Surreal(args.url)
    if hasattr(db, "connect"):
        db.connect()
    if args.namespace or args.database:
        db.use(args.namespace, args.database)
    if args.no_auth:
        pass
    elif args.token:
        db.authenticate(args.token)
    else:
        db.signin({"username": args.user, "password": args.password})
    return db


def import_record(db: Any, rid: RecordID, row: dict[str, Any], replace: bool) -> Any:
    if replace:
        return db.upsert(rid, row)
    return db.create(rid, row)


def main() -> int:
    args = parse_args()
    path = Path(args.geojson)
    if not path.exists():
        print(f"GeoJSON file not found: {path}", file=sys.stderr)
        return 1

    iterator = iter_transformed(path, args.limit)

    if args.dry_run:
        try:
            rid, row = next(iterator)
        except StopIteration:
            print("No features found.", file=sys.stderr)
            return 1
        print(rid)
        print(json.dumps(to_jsonable(row), ensure_ascii=False, indent=2))
        return 0

    imported = 0
    started = time.monotonic()
    db = connect(args)
    try:
        for rid, row in iterator:
            import_record(db, rid, row, args.replace)
            imported += 1
            if imported % args.batch_size == 0:
                elapsed = max(time.monotonic() - started, 0.001)
                print(
                    f"imported={imported} rate={imported / elapsed:.1f}/s", flush=True
                )
    finally:
        db.close()

    elapsed = max(time.monotonic() - started, 0.001)
    print(
        f"done imported={imported} elapsed={elapsed:.1f}s rate={imported / elapsed:.1f}/s"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
