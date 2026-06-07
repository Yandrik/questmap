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
