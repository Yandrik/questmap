-- Schema initialisation: create tables and fields if not already present

DEFINE TABLE IF NOT EXISTS trip SCHEMAFULL;

DEFINE FIELD IF NOT EXISTS start_time     ON TABLE trip TYPE datetime;
DEFINE FIELD IF NOT EXISTS start_location ON TABLE trip TYPE geometry<point>;
DEFINE FIELD IF NOT EXISTS end_time       ON TABLE trip TYPE datetime;
DEFINE FIELD IF NOT EXISTS end_location   ON TABLE trip TYPE geometry<point>;
DEFINE FIELD IF NOT EXISTS activities                    ON TABLE trip TYPE array<object> DEFAULT [];
DEFINE FIELD IF NOT EXISTS activities[*]                 ON TABLE trip TYPE object;
DEFINE FIELD IF NOT EXISTS activities[*].type            ON TABLE trip TYPE string;
DEFINE FIELD IF NOT EXISTS activities[*].duration_minutes ON TABLE trip TYPE int;
DEFINE FIELD IF NOT EXISTS activities[*].specification   ON TABLE trip TYPE option<string>;

DEFINE TABLE IF NOT EXISTS route SCHEMAFULL;

DEFINE FIELD IF NOT EXISTS name    ON TABLE route TYPE string;
DEFINE FIELD IF NOT EXISTS trip_id ON TABLE route TYPE string;
DEFINE FIELD IF NOT EXISTS steps              ON TABLE route TYPE array<object> DEFAULT [];
DEFINE FIELD IF NOT EXISTS steps[*]           ON TABLE route TYPE object;
DEFINE FIELD IF NOT EXISTS steps[*].type      ON TABLE route TYPE string ASSERT $value IN ["path", "area", "location"];
DEFINE FIELD IF NOT EXISTS steps[*].name      ON TABLE route TYPE string;
DEFINE FIELD IF NOT EXISTS steps[*].description ON TABLE route TYPE option<string>;
DEFINE FIELD IF NOT EXISTS steps[*].duration  ON TABLE route TYPE float;
DEFINE FIELD IF NOT EXISTS steps[*].area      ON TABLE route TYPE option<geometry<polygon>>;
DEFINE FIELD IF NOT EXISTS steps[*].path      ON TABLE route TYPE option<geometry<line>>;
DEFINE FIELD IF NOT EXISTS steps[*].location  ON TABLE route TYPE option<geometry<point>>;

DEFINE TABLE IF NOT EXISTS trip_planning_route_candidate SCHEMAFULL;

DEFINE FIELD IF NOT EXISTS sessionId       ON TABLE trip_planning_route_candidate TYPE string;
DEFINE FIELD IF NOT EXISTS legKey          ON TABLE trip_planning_route_candidate TYPE string;
DEFINE FIELD IF NOT EXISTS `from`          ON TABLE trip_planning_route_candidate TYPE object;
DEFINE FIELD IF NOT EXISTS `from`.lat      ON TABLE trip_planning_route_candidate TYPE float;
DEFINE FIELD IF NOT EXISTS `from`.lon      ON TABLE trip_planning_route_candidate TYPE float;
DEFINE FIELD IF NOT EXISTS `from`.label    ON TABLE trip_planning_route_candidate TYPE option<string>;
DEFINE FIELD IF NOT EXISTS `to`            ON TABLE trip_planning_route_candidate TYPE object;
DEFINE FIELD IF NOT EXISTS `to`.lat        ON TABLE trip_planning_route_candidate TYPE float;
DEFINE FIELD IF NOT EXISTS `to`.lon        ON TABLE trip_planning_route_candidate TYPE float;
DEFINE FIELD IF NOT EXISTS `to`.label      ON TABLE trip_planning_route_candidate TYPE option<string>;
DEFINE FIELD IF NOT EXISTS departAt        ON TABLE trip_planning_route_candidate TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS arriveBy        ON TABLE trip_planning_route_candidate TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS mode            ON TABLE trip_planning_route_candidate TYPE string ASSERT $value IN ["walk", "bike", "drive", "publicTransport"];
DEFINE FIELD IF NOT EXISTS durationSeconds ON TABLE trip_planning_route_candidate TYPE int;
DEFINE FIELD IF NOT EXISTS distanceMeters  ON TABLE trip_planning_route_candidate TYPE option<float>;
DEFINE FIELD IF NOT EXISTS geometry        ON TABLE trip_planning_route_candidate TYPE array<object> DEFAULT [];
DEFINE FIELD IF NOT EXISTS geometry[*]     ON TABLE trip_planning_route_candidate TYPE object;
DEFINE FIELD IF NOT EXISTS geometry[*].lat ON TABLE trip_planning_route_candidate TYPE float;
DEFINE FIELD IF NOT EXISTS geometry[*].lon ON TABLE trip_planning_route_candidate TYPE float;
DEFINE FIELD IF NOT EXISTS geometry[*].label ON TABLE trip_planning_route_candidate TYPE option<string>;
DEFINE FIELD OVERWRITE segments           ON TABLE trip_planning_route_candidate TYPE array<object> DEFAULT [];
DEFINE FIELD OVERWRITE segments[*]        ON TABLE trip_planning_route_candidate TYPE object FLEXIBLE;
DEFINE FIELD IF NOT EXISTS summary         ON TABLE trip_planning_route_candidate TYPE string;
DEFINE FIELD IF NOT EXISTS provider        ON TABLE trip_planning_route_candidate TYPE string;
DEFINE FIELD OVERWRITE rawProviderPayload ON TABLE trip_planning_route_candidate TYPE option<object> FLEXIBLE;
DEFINE FIELD IF NOT EXISTS selectedAt      ON TABLE trip_planning_route_candidate TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS createdAt       ON TABLE trip_planning_route_candidate TYPE datetime;

DEFINE INDEX IF NOT EXISTS trip_planning_route_candidate_session_leg
ON TABLE trip_planning_route_candidate COLUMNS sessionId, legKey;
