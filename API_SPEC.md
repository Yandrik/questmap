# Questmap API Spec

This document defines the backend API needed by the Flutter frontend for direct
navigation and AI-assisted trip planning.

Base URL is provided to Flutter as `QUESTMAP_API_BASE_URL` and defaults to
`https://back.hack5.yandrik.dev`. Request and response JSON owned by Questmap
uses camelCase field names. Existing upstream proxy endpoints keep Valhalla and
MOTIS field names where noted.

## Common Rules

- All endpoints accept and return JSON unless the endpoint is explicitly an SSE
  stream.
- Coordinates use WGS84 decimal degrees: `{ "lat": 48.401, "lon": 9.99 }`.
- Date/time values are ISO 8601 strings with timezone whenever available.
- Unknown optional fields should be ignored by clients and preserved where
  practical by the backend.
- Validation errors return `422` with a FastAPI/Pydantic-style detail body.
- Upstream routing/transit failures return `502` unless the upstream error is a
  client/actionable error forwarded as described below.

## Health

### `GET /health`

Returns backend health.

```json
{ "status": "ok" }
```

### `GET /db/health`

Returns database health.

```json
{
  "status": "ok",
  "url": "ws://localhost:8001",
  "namespace": "questmap",
  "database": "questmap"
}
```

### `GET /routing/health`

Checks Valhalla availability.

```json
{
  "status": "ok",
  "url": "http://localhost:8002",
  "upstream": {}
}
```

Returns `503` when Valhalla is unavailable.

### `GET /transit/health`

Checks MOTIS availability.

```json
{
  "status": "ok",
  "url": "http://localhost:8010",
  "upstream": {}
}
```

Returns `503` when MOTIS is unavailable.

## Direct Navigation

The frontend asks for direct navigation after the user selects a target and a
transport mode. It normalizes returned Valhalla/MOTIS payloads into
`NavigationCandidate` locally, so v1 backend responses for these endpoints must
remain compatible with those upstream response shapes.

### `POST /routing/route`

Routes walk, bike, and drive requests through Valhalla `/route`.

Request body uses Valhalla field names. Flutter sends:

```json
{
  "locations": [
    { "lat": 48.401, "lon": 9.99, "type": "break", "name": "Start" },
    { "lat": 48.42, "lon": 10.01, "type": "break", "name": "Destination" }
  ],
  "costing": "bicycle",
  "alternates": 3,
  "directions_type": "none",
  "shape_format": "geojson",
  "units": "kilometers"
}
```

Required fields:

- `locations`: at least two Valhalla locations. V1 product flow sends exactly
  two points.
- `costing`: one of `pedestrian`, `bicycle`, `auto` for app direct navigation.

Important behavior:

- Forward the request to Valhalla.
- Keep `shape_format=geojson` support because Flutter reads either GeoJSON line
  strings or encoded polylines.
- Honor `alternates` for two-point requests. Valhalla forces alternatives to zero
  for routes with more than two waypoints, but the v1 frontend only sends two.
- Do not generate turn-by-turn directions for v1; the app sends
  `directions_type=none`.

Response body is the Valhalla route response, including:

```json
{
  "trip": {
    "summary": { "length": 2.4, "time": 720 },
    "shape": {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [[9.99, 48.401], [10.01, 48.42]]
      }
    },
    "legs": []
  },
  "alternates": [
    {
      "trip": {
        "summary": { "length": 2.8, "time": 780 },
        "legs": []
      }
    }
  ]
}
```

Error behavior:

- Forward upstream `400` and `429` as the same status with upstream text in
  `detail`.
- Return `502` for other Valhalla failures.

### `POST /transit/plan`

Plans public transport navigation through MOTIS `/api/v6/plan`.

Request body uses MOTIS field names in JSON. Flutter sends:

```json
{
  "fromPlace": "48.401,9.99",
  "toPlace": "48.42,10.01",
  "time": "2026-06-07T12:00:00.000Z",
  "detailedLegs": true,
  "detailedTransfers": true,
  "directModes": [],
  "preTransitModes": ["WALK"],
  "postTransitModes": ["WALK"],
  "transitModes": ["TRANSIT"],
  "numItineraries": 4,
  "numLegAlternatives": 3,
  "timetableView": false,
  "language": ["de", "en"]
}
```

Required fields:

- `fromPlace`: `"lat,lon"`.
- `toPlace`: `"lat,lon"`.

Important behavior:

- Forward the request to MOTIS as `/api/v6/plan` query parameters.
- Lists are serialized as comma-separated query values for MOTIS.
- Return detailed legs and detailed transfers when requested.
- Treat returned MOTIS itineraries as selectable route alternatives.

Response body is the MOTIS plan response. Flutter expects at least:

```json
{
  "itineraries": [
    {
      "id": "itinerary-1",
      "duration": 1800,
      "legs": [
        {
          "mode": "WALK",
          "from": { "name": "Start" },
          "to": { "name": "Stop A" },
          "duration": 300,
          "distance": 420,
          "legGeometry": { "points": "encoded-polyline", "precision": 6 }
        },
        {
          "mode": "TRAM",
          "displayName": "U2",
          "routeShortName": "U2",
          "from": { "name": "Stop A" },
          "to": { "name": "Stop B" },
          "duration": 900,
          "legGeometry": { "points": "encoded-polyline", "precision": 6 }
        }
      ]
    }
  ]
}
```

Error behavior:

- Forward upstream `400`, `404`, `422`, and `429` as the same status with
  upstream text in `detail`.
- Return `502` for other MOTIS failures.

## Trip Planning

Trip planning is a backend-owned AI workflow. The Flutter app sends a rough,
editable itinerary draft and then listens to an SSE event stream. The backend may
ask questions, emit partial plans, emit a final plan, and support resume after an
app restart.

### Shared Trip Schemas

#### `GeoCoordinate`

```json
{
  "lat": 48.401,
  "lon": 9.99,
  "label": "Ulm Hbf"
}
```

`label` is optional.

#### `TransportMode`

String enum:

- `walk`
- `bike`
- `drive`
- `publicTransport`

Display label for `publicTransport` in the app is `ÖPNV`.

#### `TimeConstraint`

```json
{
  "startTime": "2026-06-07T12:00:00.000Z",
  "arrivalTime": "2026-06-07T14:00:00.000Z",
  "durationMinutes": 60
}
```

Rules:

- `durationMinutes` is required and must be positive.
- `startTime` is optional.
- `arrivalTime` is optional.
- If both `startTime` and `arrivalTime` are present, the backend should validate
  that the interval can fit `durationMinutes`.

#### `LocationConstraint`

Exact selected point:

```json
{
  "type": "exactPoint",
  "point": { "lat": 48.401, "lon": 9.99, "label": "Museum" }
}
```

Around a selected point:

```json
{
  "type": "aroundPoint",
  "point": { "lat": 48.401, "lon": 9.99, "label": "City center" }
}
```

Somewhere in a circular area:

```json
{
  "type": "areaCircle",
  "center": { "lat": 48.401, "lon": 9.99 },
  "radiusMeters": 800
}
```

Backend chooses anywhere within a transport budget:

```json
{
  "type": "wherever",
  "maxTransportMinutes": 15
}
```

#### `ItineraryStepDraft`

```json
{
  "id": "step-1",
  "type": "eat",
  "title": "Eat",
  "details": "Chinese, casual dinner",
  "time": { "durationMinutes": 60 },
  "location": {
    "type": "wherever",
    "maxTransportMinutes": 15
  },
  "iconKey": "restaurant",
  "colorValue": 4293869636
}
```

`type` enum:

- `shop`
- `eat`
- `party`
- `walk`
- `sightsee`
- `meander`
- `exactLocation`

`iconKey` and `colorValue` are UI hints sent by the app; the backend can ignore
them. For `meander`, the backend may combine shopping, food, views, walking, and
nightlife based on context.

#### `TripPlan`

```json
{
  "id": "plan-1",
  "title": "Afternoon in Ulm",
  "summary": "Food, a riverside walk, and one viewpoint.",
  "items": [
    {
      "id": "travel-1",
      "type": "travel",
      "title": "Walk to the restaurant",
      "description": "A short walk through the old town.",
      "reasoning": "Walking is faster than waiting for transit here.",
      "transportMode": "walk",
      "startTime": "2026-06-07T12:00:00.000Z",
      "endTime": "2026-06-07T12:12:00.000Z",
      "geometry": [
        { "lat": 48.401, "lon": 9.99 },
        { "lat": 48.404, "lon": 9.995 }
      ]
    },
    {
      "id": "activity-1",
      "type": "activity",
      "title": "Lunch",
      "description": "Chinese lunch near the center.",
      "reasoning": "Matches the requested cuisine and timing.",
      "sourceDraftStepId": "step-1",
      "stepType": "eat",
      "startTime": "2026-06-07T12:15:00.000Z",
      "endTime": "2026-06-07T13:15:00.000Z",
      "location": { "lat": 48.404, "lon": 9.995, "label": "Restaurant" },
      "geometry": []
    }
  ]
}
```

Rules:

- `items` are ordered and represent the full route chain: travel leg, activity,
  travel leg, next activity, and so on.
- `type` is `activity` or `travel`.
- `description` should be visible by default in the app.
- `reasoning` is optional and shown on tap.
- Activity items should include `sourceDraftStepId` when derived from a draft
  step.
- Travel items should include `transportMode` and route `geometry` when
  available.
- Activity items should include `location` when the backend chose or confirmed a
  point.

### `POST /trip-planning/sessions`

Starts an AI trip-planning session.

Request:

```json
{
  "draftId": "draft-1",
  "startLocation": { "lat": 48.401, "lon": 9.99, "label": "Current location" },
  "endLocation": { "lat": 48.42, "lon": 10.01, "label": "Hotel" },
  "transportModes": ["walk", "publicTransport"],
  "steps": [
    {
      "id": "step-1",
      "type": "eat",
      "title": "Eat",
      "details": "Chinese",
      "time": { "durationMinutes": 60 },
      "location": { "type": "wherever", "maxTransportMinutes": 15 }
    }
  ]
}
```

Required fields:

- `draftId`
- `startLocation`
- `transportModes`, at least one
- `steps`, at least one for useful planning

Optional fields:

- `endLocation`

Response:

```json
{ "sessionId": "session-1" }
```

Behavior:

- Create a durable session record before returning.
- Start or enqueue the planning workflow.
- The session must be resumable through `GET /trip-planning/sessions/{sessionId}`.
- The backend owns route computation inside generated trip plans, including
  public transport legs.

### `GET /trip-planning/sessions/{sessionId}/events`

Streams live planning events using Server-Sent Events.

Headers:

- Client sends `Accept: text/event-stream`.
- Server responds with `Content-Type: text/event-stream`.

Each event payload is JSON. The SSE `event:` name may match the payload `type`,
but Flutter will use `data.type` when present.

Status event:

```text
event: status
data: {"type":"status","message":"Finding places near your route..."}

```

Question event:

```text
event: question
data: {"type":"question","question":{"id":"q1","kind":"yesNo","prompt":"Is a 12 minute walk okay?","options":[]}}

```

Partial plan event:

```text
event: partialPlan
data: {"type":"partialPlan","plan":{"id":"plan-draft","title":"Draft plan","items":[]}}

```

Final plan event:

```text
event: finalPlan
data: {"type":"finalPlan","plan":{"id":"plan-1","title":"Final plan","items":[]}}

```

Error event:

```text
event: error
data: {"type":"error","message":"No reachable public transport route was found."}

```

Done event:

```text
event: done
data: {"type":"done","message":"done"}

```

Event types:

- `status`: progress message only.
- `question`: requires a user answer before the workflow continues.
- `partialPlan`: read-only plan progress.
- `finalPlan`: final generated plan; the app persists it locally.
- `error`: terminal or recoverable error. If terminal, follow with `done`.
- `done`: stream is complete.

Keepalive comments are allowed:

```text
: keepalive

```

Question schema:

```json
{
  "id": "q1",
  "kind": "selection",
  "prompt": "Which restaurant direction do you prefer?",
  "unit": "minutes",
  "options": [
    {
      "id": "north",
      "title": "North route",
      "description": "More shops, slightly longer.",
      "imageUrl": "https://example.test/preview.jpg",
      "payload": { "routeCandidateId": "route-1" }
    }
  ]
}
```

`kind` enum:

- `yesNo`
- `number`
- `text`
- `selection`
- `routeChoice`

Question value expectations:

- `yesNo`: boolean.
- `number`: number.
- `text`: string.
- `selection`: option id string, or an object if the backend explicitly defines a
  richer option payload.
- `routeChoice`: selected route/option id string, or a route-choice object if
  specified in the question payload.

### `POST /trip-planning/sessions/{sessionId}/answers`

Posts an answer to the current agent question.

Request:

```json
{
  "questionId": "q1",
  "value": true
}
```

Response:

- `204 No Content` on success.

Behavior:

- Reject answers for unknown sessions with `404`.
- Reject stale or mismatched `questionId` with `409`.
- Validate answer type against the question `kind`; return `422` when invalid.
- After accepting an answer, continue the workflow and emit further SSE events.

### `POST /trip-planning/sessions/{sessionId}/cancel`

Cancels a running session.

Response:

- `204 No Content` on success.

Behavior:

- Mark the session as cancelled.
- Stop active work where possible.
- Existing event streams should receive either an `error` event with a
  cancellation message followed by `done`, or just `done`.
- Repeated cancellation is idempotent and should still return `204`.
- Unknown sessions return `404`.

### `GET /trip-planning/sessions/{sessionId}`

Returns a session snapshot for app restart/resume.

Response:

```json
{
  "sessionId": "session-1",
  "draftId": "draft-1",
  "state": "waitingForAnswer",
  "request": {
    "draftId": "draft-1",
    "startLocation": { "lat": 48.401, "lon": 9.99 },
    "transportModes": ["walk", "publicTransport"],
    "steps": []
  },
  "currentQuestion": {
    "id": "q1",
    "kind": "yesNo",
    "prompt": "Is a 12 minute walk okay?",
    "options": []
  },
  "latestPartialPlan": null,
  "finalPlan": null,
  "lastMessage": "Waiting for your answer.",
  "createdAt": "2026-06-07T12:00:00.000Z",
  "updatedAt": "2026-06-07T12:02:00.000Z"
}
```

`state` enum:

- `queued`
- `running`
- `waitingForAnswer`
- `completed`
- `failed`
- `cancelled`

Rules:

- Return `404` for unknown sessions.
- Include `currentQuestion` only when waiting for an answer.
- Include `latestPartialPlan` when available.
- Include `finalPlan` when completed.
- A client may reconnect to `/events` after reading this snapshot.

## Backend-Owned Persistence

The Flutter app persists drafts, final plans, active agent sessions, and trip
progress locally. The backend still needs durable trip-planning session storage
for:

- returning `sessionId` only after a session can be resumed,
- reconnecting an SSE stream,
- validating posted answers,
- cancellation,
- exposing session snapshots.

Backend storage of final user plan history and multi-device sync are out of v1.

## Out of Scope for V1

- Turn-by-turn instructions and lane guidance.
- Automatic rerouting during active navigation.
- Payment, ticketing, or fare purchase.
- Backend-owned saved plan history beyond active/resumable planning sessions.
- Multi-device sync.
