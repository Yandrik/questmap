import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:watch_it/watch_it.dart';

import 'package:meander/_shared/models/geo_coordinate.dart';
import 'package:meander/_shared/services/api_client.dart';
import 'package:meander/_shared/services/local_persistence_service.dart';
import 'package:meander/features/map/manager/map_interaction_manager.dart';
import 'package:meander/features/map/model/rendered_map_feature.dart';
import 'package:meander/features/map/model/selected_map_target.dart';
import 'package:meander/features/trip_planning/manager/trip_agent_manager.dart';
import 'package:meander/features/trip_planning/manager/trip_draft_manager.dart';
import 'package:meander/features/trip_planning/manager/trip_plan_manager.dart';
import 'package:meander/features/trip_planning/model/itinerary_step_draft.dart';
import 'package:meander/features/trip_planning/model/location_constraint.dart';
import 'package:meander/features/trip_planning/model/pending_trip_location_pick.dart';
import 'package:meander/features/trip_planning/model/trip_plan.dart';
import 'package:meander/features/trip_planning/services/trip_planning_api_service.dart';
import 'package:meander/features/trip_planning/widgets/trip_composer_panel.dart';

void main() {
  setUp(() async {
    await di.reset();
    di.registerLazySingleton<ApiClient>(
      () => ApiClient(baseUrl: 'http://api.test'),
      dispose: (client) => client.dispose(),
    );
    di.registerLazySingleton<LocalPersistenceService>(
      () => LocalPersistenceService(MemoryLocalPersistenceStore()),
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

    expect(find.byTooltip('Insert activity here'), findsWidgets);
    await tester.tap(find.byTooltip('Insert activity here').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(manager.draft!.steps.map((step) => step.type), [
      ItineraryStepType.shop,
      ItineraryStepType.meander,
      ItineraryStepType.eat,
    ]);
  });

  testWidgets('shows inline add buttons before and after a single activity', (
    tester,
  ) async {
    final manager = di<TripDraftManager>();
    manager.addStep(
      type: ItineraryStepType.shop,
      details: 'clothes',
      location: LocationConstraint.wherever(),
    );

    await _pumpPanel(tester);

    expect(find.byTooltip('Insert activity here'), findsNWidgets(2));
  });

  testWidgets('shows start and end location inputs and starts map picking', (
    tester,
  ) async {
    await _pumpPanel(tester);

    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Lat 48.400000, Lon 9.990000'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);
    expect(find.text('Add end location'), findsOneWidget);

    await tester.tap(find.text('Lat 48.400000, Lon 9.990000'));
    await tester.pumpAndSettle();
    expect(
      di<TripDraftManager>().pendingLocationPick!.target.type,
      TripLocationPickTargetType.startLocation,
    );
    expect(di<MapInteractionManager>().mode, MapInteractionMode.selectStart);

    di<TripDraftManager>().cancelLocationPick();
    await tester.tap(find.text('Add end location'));
    await tester.pumpAndSettle();
    expect(
      di<TripDraftManager>().pendingLocationPick!.target.type,
      TripLocationPickTargetType.endLocation,
    );
    expect(di<MapInteractionManager>().mode, MapInteractionMode.selectEnd);
  });

  testWidgets('shows compact location input only for located activities', (
    tester,
  ) async {
    final manager = di<TripDraftManager>();
    manager.addStep(
      type: ItineraryStepType.shop,
      details: 'clothes',
      location: LocationConstraint.exactPoint(
        const GeoCoordinate(lat: 48.41, lon: 10, label: 'Mall'),
      ),
    );
    manager.addStep(
      type: ItineraryStepType.eat,
      details: 'Chinese',
      location: LocationConstraint.wherever(),
    );

    await _pumpPanel(tester);

    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Mall'), findsOneWidget);

    await tester.tap(find.text('Mall'));
    await tester.pumpAndSettle();
    final pending = manager.pendingLocationPick!;
    expect(pending.target.type, TripLocationPickTargetType.stepLocation);
    expect(pending.target.stepId, manager.draft!.steps.first.id);
  });

  testWidgets('edits an activity from its icon', (tester) async {
    final manager = di<TripDraftManager>();
    manager.addStep(
      type: ItineraryStepType.shop,
      details: 'clothes',
      location: LocationConstraint.wherever(),
    );

    await _pumpPanel(tester);

    await tester.tap(find.byTooltip('Edit activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eat').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ramen');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final step = manager.draft!.steps.single;
    expect(step.type, ItineraryStepType.eat);
    expect(step.title, 'Eat');
    expect(step.details, 'ramen');
  });

  testWidgets('shows readable wrapping location choice labels in dialog', (
    tester,
  ) async {
    await _pumpPanel(tester);

    await tester.tap(find.text('Add activity'));
    await tester.pumpAndSettle();

    expect(find.text('Wherever'), findsOneWidget);
    expect(find.text('Around here'), findsOneWidget);
    expect(find.text('Area'), findsOneWidget);
    expect(find.text('Exact'), findsOneWidget);
  });

  testWidgets('shows activity type chips with icons', (tester) async {
    await _pumpPanel(tester);

    await tester.tap(find.text('Add activity'));
    await tester.pumpAndSettle();

    expect(find.widgetWithIcon(ChoiceChip, Icons.shopping_bag), findsOneWidget);
    expect(find.widgetWithIcon(ChoiceChip, Icons.restaurant), findsOneWidget);
    expect(find.widgetWithIcon(ChoiceChip, Icons.nightlife), findsOneWidget);
    expect(
      find.widgetWithIcon(ChoiceChip, Icons.directions_walk),
      findsOneWidget,
    );
    expect(find.widgetWithIcon(ChoiceChip, Icons.photo_camera), findsOneWidget);
    expect(find.widgetWithIcon(ChoiceChip, Icons.auto_awesome), findsOneWidget);
    expect(find.widgetWithIcon(ChoiceChip, Icons.place), findsWidgets);
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

  testWidgets('stores feature labels with coordinates from selected target', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      selectedTarget: SelectedMapTarget.feature(
        feature: const RenderedMapFeature(
          layerId: 'poi',
          sourceLayer: 'poi',
          properties: {'name': 'Museum'},
          coordinates: LatLng(48.398, 9.992),
        ),
        fallbackCoordinates: const LatLng(48.398, 9.992),
      ),
    );

    await tester.tap(find.text('Add activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exact'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use selected target'));
    await tester.pumpAndSettle();

    final step = di<TripDraftManager>().draft!.steps.single;
    expect(step.location.point!.label, 'Museum (48.398000, 9.992000)');
  });

  testWidgets('keeps returned plan in composer until started', (tester) async {
    var closed = false;
    await di<TripPlanManager>().setPlan(_reviewPlan());

    await _pumpPanel(tester, onClose: () => closed = true);

    expect(find.text('Review trip'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pump();

    expect(di<TripPlanManager>().isTripActive, isTrue);
    expect(closed, isTrue);
  });

  testWidgets('rejects returned plan and stays in editable composer', (
    tester,
  ) async {
    await di<TripPlanManager>().setPlan(_reviewPlan());

    await _pumpPanel(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await tester.pump();

    expect(di<TripPlanManager>().currentPlan, isNull);
    expect(find.text('Add activity'), findsOneWidget);
  });
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  SelectedMapTarget? selectedTarget,
  VoidCallback? onClose,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 430,
          height: 720,
          child: TripComposerPanel(
            selectedTarget: selectedTarget,
            onClose: onClose ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TripPlan _reviewPlan() {
  return const TripPlan(
    id: 'plan-1',
    title: 'Review trip',
    summary: '1 planned stop with routed travel legs.',
    items: [
      TripPlanItem(
        id: 'activity-1',
        type: TripPlanItemType.activity,
        title: 'Shop',
        description: 'books',
      ),
    ],
  );
}
