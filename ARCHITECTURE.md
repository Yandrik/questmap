# Meander Architecture

This document describes the current Flutter app architecture and the rules for
growing it as routing, transit, backend integration, and AI trip
planning are added.

## High-Level Shape

Meander uses a feature-first Flutter structure based on Pragmatic Flutter
Architecture:

- Services wrap external boundaries: HTTP APIs, platform services, map SDK
  helpers, persistence, and OS permissions.
- Managers own business workflows and expose reactive state and commands to UI.
- Views and widgets render UI, read manager state, and call manager actions.

The FastAPI backend is the main app boundary for production features. The
Flutter app should prefer backend endpoints over direct calls to Valhalla,
MOTIS, AI providers, or the database. Direct upstream clients can exist as
development or low-level transport helpers, but product workflows should be
modeled around backend-facing services.

## Flutter App Layout

```text
app/lib/
  main.dart
  app/
    app_config.dart
    app_theme.dart
    bootstrap.dart
    meander.dart
  _shared/
    models/
    services/
    widgets/
  features/
    location/
      manager/
      model/
      services/
    map/
      manager/
      model/
      pages/
      services/
      widgets/
    routing/
      manager/
      model/
      services/
    transit/
      manager/
      model/
      services/
    trip_planning/
      manager/
      model/
      services/
```

`main.dart` stays thin. It should only delegate to app bootstrap code.

`app/` contains app-wide composition: startup, root widget, theme, constants,
routing setup when introduced, and future dependency registration entry points.

`_shared/` is only for code used by multiple features. Do not put code there
preemptively. Start in a feature, then move to `_shared/` when at least two
features need it.

`features/` contains product areas. Each feature owns its models, services,
managers, pages, and widgets unless the code is genuinely shared.

## Feature Folder Roles

`pages/`
: Full-screen or high-level feature views. Pages may own UI lifecycle objects
such as controllers from platform views. For example, `MapLibreMapController`
belongs in the map page layer because it is tied to the rendered map widget.

`widgets/`
: Feature-specific reusable UI pieces. Widgets should render state and call
callbacks or manager actions. They should not directly call HTTP services.

`model/`
: Domain objects, DTOs, request objects, response objects, and feature proxies.
Models should avoid importing Flutter UI packages unless the type is explicitly
UI or SDK-bound. For map models, `LatLng` is currently accepted because selected
targets are MapLibre-derived.

`services/`
: External and technical boundaries. Examples include Dio clients, MapLibre
style helpers, icon registration, location permission services, and backend API
services. Services should not own app state.

`manager/`
: Business workflows and state. Managers should coordinate services, expose
`ValueListenable` state, and provide commands for user-triggered async actions.
Managers are intentionally not one-to-one view models.

## Current Implemented Boundaries

The app shell is split into:

- `app/bootstrap.dart`: Flutter initialization and startup services.
- `app/meander.dart`: root `MaterialApp`.
- `app/app_config.dart`: shared app constants.
- `app/app_theme.dart`: root theme construction.

The map feature is split into:

- `features/map/pages/map_shell.dart`: MapLibre widget, map controller
  lifecycle, location callbacks, and page composition.
- `features/map/model/rendered_map_feature.dart`: normalized rendered feature
  data from MapLibre query results.
- `features/map/model/selected_map_target.dart`: selected POI or waypoint.
- `features/map/services/map_feature_hit_tester.dart`: nearest-feature logic.
- `features/map/services/map_icon_catalog.dart`: style icon catalog and
  feature-to-icon mapping.
- `features/map/services/map_icon_registry.dart`: SVG-to-PNG registration for
  MapLibre.
- `features/map/services/map_selection_overlay.dart`: selection circle and
  waypoint symbol operations.
- `features/map/services/map_style_config.dart`: map style IDs, layers, and
  initial camera constants.
- `features/map/widgets/*`: map panel, title badge, and location button.

Routing and transit are split into:

- `features/routing/model/valhalla_route_request.dart`
- `features/routing/services/valhalla_client.dart`
- `features/transit/model/motis_plan_request.dart`
- `features/transit/services/motis_client.dart`

These current clients still target upstream Valhalla and MOTIS directly. As
app workflows mature, add backend-facing services beside or in place of them,
for example `RoutingApiService` and `TransitApiService`.

## Dependency Direction

Keep dependencies flowing inward and downward:

- Pages and widgets may depend on managers, models, and feature widgets.
- Managers may depend on services, models, and other managers when there is a
  clear domain relationship.
- Services may depend on transport packages and external SDKs.
- Models should stay mostly independent.
- Shared code must not depend on feature code.
- Feature code should not import another feature's private implementation
  details. If cross-feature data is needed, move the common model to `_shared/`
  or expose it through a manager/service boundary.

Avoid barrel files until imports become noisy. Direct imports make ownership
clear while the app is still small.

## State Management Direction

The app is prepared for the flutter_it construction set, but the packages should
be added incrementally:

1. Add `get_it` when dependency registration becomes useful.
2. Add `watch_it` for widgets that rebuild from manager state.
3. Add `command_it` for user-triggered async actions with loading and errors.
4. Use `listen_it` for side effects outside widgets.

Managers should expose `ValueListenable` state and commands. UI-triggered async
work should be represented as commands once `command_it` is introduced. Manager
`init()` methods may call services directly for initial data loading; commands
are for UI actions.

Do not put `MapLibreMapController` in global dependency injection. Keep it in
the map page or a page-owned adapter because its lifecycle belongs to the map
widget.

## Backend Integration Rules

Use a single backend base URL configuration for app API calls, preferably via
`--dart-define`, for example:

```sh
--dart-define=QUESTMAP_API_BASE_URL=https://back.hack5.yandrik.dev
```

Backend-facing services should be feature-owned:

- `features/routing/services/routing_api_service.dart` for `/routing/route`
- `features/transit/services/transit_api_service.dart` for `/transit/plan`
- `features/trip_planning/services/trip_planning_api_service.dart` for future
  AI trip-planning endpoints

The Flutter app should not call AI providers, SurrealDB, or routing engines
directly in product flows. Those decisions belong in the backend.

## Adding a New Feature

When adding a feature:

1. Create folders under `features/<feature>/`.
2. Put request/response/domain objects in `model/`.
3. Put HTTP or platform boundaries in `services/`.
4. Put business workflows in `manager/`.
5. Put screens in `pages/`.
6. Put feature-specific UI pieces in `widgets/`.
7. Add tests next to the existing test structure, named for the feature or unit
   under test.

Only promote code to `_shared/` after reuse is real.

## Testing Strategy

Keep tests focused on boundaries:

- Model tests for serialization, parsing, formatting, and validation.
- Service tests for request shape, endpoint paths, and error mapping.
- Manager tests with fake services for business workflows.
- Widget tests for panels, buttons, and state-specific rendering.
- Smoke tests for full pages where platform-view behavior is hard to unit test.

Run these before handing off app architecture changes:

```sh
cd app
dart format lib test
flutter analyze
flutter test
```

## Migration Priorities

Near-term architecture work should happen in this order:

1. Introduce a backend `ApiClient` and backend-facing routing/transit services.
2. Move location permission handling into `features/location`.
3. Add `get_it` registration once services/managers need composition.
4. Add `MapSelectionManager` for selected target and query state.
5. Add route/transit planning managers with commands.
6. Add typed backend result models instead of passing raw JSON maps to UI.
The main goal is to keep product workflows out of pages while keeping SDK
controller lifecycle code close to the widgets that own it.
