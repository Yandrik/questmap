import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:watch_it/watch_it.dart';

import 'package:meander/_shared/models/geo_coordinate.dart';
import 'package:meander/_shared/services/api_client.dart';
import 'package:meander/_shared/services/local_database.dart';
import 'package:meander/_shared/services/local_persistence_service.dart';
import 'package:meander/features/map/manager/map_interaction_manager.dart';
import 'package:meander/features/map/model/selected_map_target.dart';
import 'package:meander/features/trip_planning/manager/trip_agent_manager.dart';
import 'package:meander/features/trip_planning/manager/trip_draft_manager.dart';
import 'package:meander/features/trip_planning/manager/trip_plan_manager.dart';
import 'package:meander/features/trip_planning/model/itinerary_step_draft.dart';
import 'package:meander/features/trip_planning/model/location_constraint.dart';
import 'package:meander/features/trip_planning/model/pending_trip_location_pick.dart';
import 'package:meander/features/trip_planning/services/trip_planning_api_service.dart';
import 'package:meander/features/trip_planning/widgets/trip_composer_panel.dart';

void main() {
  late LocalDatabase database;

  setUp(() async {
    await di.reset();
    database = LocalDatabase(NativeDatabase.memory());
    di.registerLazySingleton<ApiClient>(
      () => ApiClient(baseUrl: 'http://api.test'),
      dispose: (client) => client.dispose(),
    );
    di.registerLazySingleton<LocalDatabase>(
      () => database,
      dispose: (database) => database.close(),
    );
    di.registerLazySingleton<LocalPersistenceService>(
      () => LocalPersistenceService(di<LocalDatabase>()),
    );
    di.registerLazySingleton<MapInteractionManager>(
      () => MapInteractionManager(),
      dispose: (manager) => manager.dispose(),
    );
    di.registerLazySingleton<TripPlanningApiService>(
      () => TripPlanningApiService(di<ApiClient>()),
    );
    di.registerLazySingleton<TripDraftManager>(
      () => TripDraftManager(di<LocalPersistenceService>()),
      dispose: (manager) => manager.dispose(),
    );
    di.registerLazySingleton<TripPlanManager>(
      () => TripPlanManager(di<LocalPersistenceService>()),
      dispose: (manager) => manager.dispose(),
    );
    di.registerLazySingleton<TripAgentManager>(
      () => TripAgentManager(
        di<TripPlanningApiService>(),
        di<TripPlanManager>(),
        di<LocalPersistenceService>(),
      ),
      dispose: (manager) => manager.dispose(),
    );
    await di<TripDraftManager>().ensureDraft(
      startLocation: const GeoCoordinate(lat: 48.4, lon: 9.99),
    );
  });

  tearDown(() async {
    await di.reset();
  });

  testWidgets('inserts an activity between itinerary steps', (tester) async {
    final manager = di<TripDraftManager>();
    manager.addStep(
      type: ItineraryStepType.shop,
      details: 'clothes',
      location: LocationConstraint.wherever(),
    );
    manager.addStep(
      type: ItineraryStepType.eat,
      details: 'Chinese',
      location: LocationConstraint.wherever(),
    );

    await _pumpPanel(tester);

    expect(find.byTooltip('Insert activity here'), findsOneWidget);
    await tester.tap(find.byTooltip('Insert activity here'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(manager.draft!.steps.map((step) => step.type), [
      ItineraryStepType.shop,
      ItineraryStepType.meander,
      ItineraryStepType.eat,
    ]);
  });

  testWidgets('starts exact-location map picking without selected target', (
    tester,
  ) async {
    await _pumpPanel(tester);

    await tester.tap(find.text('Add activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exact location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick on map'));
    await tester.pumpAndSettle();

    final pending = di<TripDraftManager>().pendingLocationPick;
    expect(pending!.type, ItineraryStepType.exactLocation);
    expect(pending.kind, TripLocationPickKind.exactPoint);
    expect(di<MapInteractionManager>().mode, MapInteractionMode.selectPoint);
  });

  testWidgets('starts area map picking without selected target', (
    tester,
  ) async {
    await _pumpPanel(tester);

    await tester.tap(find.text('Add activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Area'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick on map'));
    await tester.pumpAndSettle();

    final pending = di<TripDraftManager>().pendingLocationPick;
    expect(pending!.kind, TripLocationPickKind.areaCircle);
    expect(di<MapInteractionManager>().mode, MapInteractionMode.drawArea);
  });

  testWidgets('uses selected target for point location choices', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      selectedTarget: SelectedMapTarget.waypoint(
        coordinates: const LatLng(48.398, 9.992),
      ),
    );

    await tester.tap(find.text('Add activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Around here'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use selected target'));
    await tester.pumpAndSettle();

    final step = di<TripDraftManager>().draft!.steps.single;
    expect(step.location.type, LocationConstraintType.aroundPoint);
    expect(step.location.point!.lat, 48.398);
  });
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  SelectedMapTarget? selectedTarget,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 430,
          height: 720,
          child: TripComposerPanel(
            selectedTarget: selectedTarget,
            onClose: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
