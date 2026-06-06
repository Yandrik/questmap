import 'package:watch_it/watch_it.dart';

import '_shared/services/api_client.dart';
import '_shared/services/local_database.dart';
import '_shared/services/local_persistence_service.dart';
import 'app/app_config.dart';
import 'features/routing/services/routing_api_service.dart';
import 'features/transit/services/transit_api_service.dart';
import 'features/trip_planning/services/trip_planning_api_service.dart';

void configureDependencies() {
  if (di.isRegistered<ApiClient>()) return;

  di.registerLazySingleton<ApiClient>(
    () => ApiClient(baseUrl: appApiBaseUrl),
    dispose: (client) => client.dispose(),
  );
  di.registerLazySingleton<LocalDatabase>(
    () => LocalDatabase(openLocalDatabaseConnection()),
    dispose: (database) => database.close(),
  );
  di.registerLazySingleton<LocalPersistenceService>(
    () => LocalPersistenceService(di<LocalDatabase>()),
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
}
