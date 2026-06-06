DEFINE TABLE osm_object SCHEMAFULL;

DEFINE FIELD osm_type ON TABLE osm_object TYPE string
  ASSERT $value IN ["node", "area"];

DEFINE FIELD osm_id ON TABLE osm_object TYPE int;

DEFINE FIELD location ON TABLE osm_object TYPE geometry<point>;

DEFINE FIELD lon ON TABLE osm_object TYPE float;
DEFINE FIELD lat ON TABLE osm_object TYPE float;

DEFINE FIELD primary_family ON TABLE osm_object TYPE option<string>;
DEFINE FIELD primary_type ON TABLE osm_object TYPE option<string>;

DEFINE FIELD name ON TABLE osm_object TYPE option<string>;
DEFINE FIELD operator ON TABLE osm_object TYPE option<string>;
DEFINE FIELD ref ON TABLE osm_object TYPE option<string>;
DEFINE FIELD brand ON TABLE osm_object TYPE option<string>;
DEFINE FIELD website ON TABLE osm_object TYPE option<string>;
DEFINE FIELD phone ON TABLE osm_object TYPE option<string>;
DEFINE FIELD email ON TABLE osm_object TYPE option<string>;
DEFINE FIELD opening_hours ON TABLE osm_object TYPE option<string>;

DEFINE FIELD address ON TABLE osm_object TYPE object;
DEFINE FIELD address.country ON TABLE osm_object TYPE option<string>;
DEFINE FIELD address.postcode ON TABLE osm_object TYPE option<string>;
DEFINE FIELD address.city ON TABLE osm_object TYPE option<string>;
DEFINE FIELD address.street ON TABLE osm_object TYPE option<string>;
DEFINE FIELD address.housenumber ON TABLE osm_object TYPE option<string>;
DEFINE FIELD address.suburb ON TABLE osm_object TYPE option<string>;

DEFINE FIELD access ON TABLE osm_object TYPE option<string>;
DEFINE FIELD wheelchair ON TABLE osm_object TYPE option<string>;
DEFINE FIELD fee ON TABLE osm_object TYPE option<string>;

-- Full original OSM properties/tags, including long-tail keys like
-- "fire_hydrant:diameter", "generator:source", "railway:signal:main", etc.
DEFINE FIELD tags ON TABLE osm_object TYPE object FLEXIBLE;

DEFINE INDEX osm_object_osm_unique
  ON TABLE osm_object
  FIELDS osm_type, osm_id
  UNIQUE;

DEFINE INDEX osm_object_primary_type
  ON TABLE osm_object
  FIELDS primary_family, primary_type;

DEFINE INDEX osm_object_name
  ON TABLE osm_object
  FIELDS name;