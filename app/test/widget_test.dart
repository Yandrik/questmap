import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:watch_it/watch_it.dart';

import 'package:meander/_shared/services/api_client.dart';
import 'package:meander/_shared/services/local_persistence_service.dart';
import 'package:meander/app/meander.dart';
import 'package:meander/features/location/manager/location_manager.dart';
import 'package:meander/features/map/manager/map_interaction_manager.dart';
import 'package:meander/features/map/manager/map_selection_manager.dart';
import 'package:meander/features/routing/manager/routing_manager.dart';
import 'package:meander/features/routing/services/routing_api_service.dart';
import 'package:meander/features/transit/services/transit_api_service.dart';
import 'package:meander/features/trip_planning/manager/trip_agent_manager.dart';
import 'package:meander/features/trip_planning/manager/trip_draft_manager.dart';
import 'package:meander/features/trip_planning/manager/trip_plan_manager.dart';
import 'package:meander/features/trip_planning/services/trip_planning_api_service.dart';

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
    di.registerLazySingleton<RoutingApiService>(
      () => RoutingApiService(di<ApiClient>()),
    );
    di.registerLazySingleton<TransitApiService>(
      () => TransitApiService(di<ApiClient>()),
    );
    di.registerLazySingleton<TripPlanningApiService>(
      () => TripPlanningApiService(di<ApiClient>()),
    );
    di.registerLazySingleton<LocationManager>(
      () => LocationManager(),
      dispose: (manager) => manager.dispose(),
    );
    di.registerLazySingleton<MapSelectionManager>(
      () => MapSelectionManager(),
      dispose: (manager) => manager.dispose(),
    );
    di.registerLazySingleton<MapInteractionManager>(
      () => MapInteractionManager(),
      dispose: (manager) => manager.dispose(),
    );
    di.registerLazySingleton<RoutingManager>(
      () => RoutingManager(di<RoutingApiService>(), di<TransitApiService>()),
      dispose: (manager) => manager.dispose(),
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
  });

  tearDown(() async {
    await di.reset();
  });

  testWidgets('renders the MapLibre OMT map shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MeanderApp());

    expect(find.text('Meander'), findsOneWidget);
    expect(find.byType(MapLibreMap), findsOneWidget);
    expect(find.text('Map target'), findsOneWidget);

    final map = tester.widget<MapLibreMap>(find.byType(MapLibreMap));
    expect(map.styleString, equals('assets/omt_style.json'));
    expect(
      map.initialCameraPosition,
      equals(
        const CameraPosition(target: LatLng(37.7749, -122.4194), zoom: 16),
      ),
    );
  });
}
