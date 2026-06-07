import 'package:watch_it/watch_it.dart';

import '_shared/services/api_client.dart';
import '_shared/services/local_persistence_service.dart';
import 'app/app_config.dart';
import 'features/location/manager/location_manager.dart';
import 'features/map/manager/map_interaction_manager.dart';
import 'features/map/manager/map_selection_manager.dart';
import 'features/routing/manager/routing_manager.dart';
import 'features/routing/services/routing_api_service.dart';
import 'features/transit/services/transit_api_service.dart';
import 'features/trip_planning/manager/trip_agent_manager.dart';
import 'features/trip_planning/manager/trip_draft_manager.dart';
import 'features/trip_planning/manager/trip_plan_manager.dart';
import 'features/trip_planning/services/trip_planning_api_service.dart';

void configureDependencies() {
  if (di.isRegistered<ApiClient>()) return;

  di.registerLazySingleton<ApiClient>(
    () => ApiClient(baseUrl: appApiBaseUrl),
    dispose: (client) => client.dispose(),
  );
  di.registerLazySingleton<LocalPersistenceService>(
    () => LocalPersistenceService(),
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
}
