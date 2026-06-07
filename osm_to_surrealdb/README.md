# OSM to SurrealDB

Small helper scripts for converting an OpenStreetMap `.osm.pbf` extract to GeoJSON and importing it into SurrealDB.

## Setup

Install the Python dependencies:

```bash
uv sync
```

## 1. Convert OSM PBF to GeoJSON

Download an `.osm.pbf` extract from a provider such as [Geofabrik](https://download.geofabrik.de/).

Example for Tuebingen:

```bash
uv run python osm_objects_to_geojson.py ~/Downloads/tuebingen-regbez-260604.osm.pbf -o tuebingen.geojson
```

## 2. Create the SurrealDB Table

Run the schema in `osm_table.surql` against your SurrealDB instance before importing data. (Auto run in step 3)

## 3. Import the GeoJSON

```bash
uv run python import_geojson_to_surreal.py \
  --url ws://127.0.0.1:8001 \
  --user root \
  --password root \
  --namespace main \
  --database main \
  ./tuebingen.geojson
```
