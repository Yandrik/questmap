import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_it/watch_it.dart';

import 'package:meander/_shared/models/geo_coordinate.dart';
import 'package:meander/_shared/services/api_client.dart';
import 'package:meander/_shared/services/local_persistence_service.dart';
import 'package:meander/features/trip_planning/manager/trip_agent_manager.dart';
import 'package:meander/features/trip_planning/manager/trip_plan_manager.dart';
import 'package:meander/features/trip_planning/model/trip_draft.dart';
import 'package:meander/features/trip_planning/model/trip_planning_session.dart';
import 'package:meander/features/trip_planning/services/trip_planning_api_service.dart';
import 'package:meander/features/trip_planning/widgets/trip_planning_overlay.dart';

void main() {
  late _FakeTripPlanningApiService api;

  setUp(() async {
    await di.reset();
    api = _FakeTripPlanningApiService();
    di.registerSingleton<LocalPersistenceService>(
      LocalPersistenceService(MemoryLocalPersistenceStore()),
    );
    di.registerSingleton<TripPlanManager>(
      TripPlanManager(di<LocalPersistenceService>()),
      dispose: (manager) => manager.dispose(),
    );
    di.registerSingleton<TripAgentManager>(
      TripAgentManager(
        api,
        di<TripPlanManager>(),
        di<LocalPersistenceService>(),
      ),
      dispose: (manager) => manager.dispose(),
    );
  });

  tearDown(() async {
    await di.reset();
    await api.close();
  });

  testWidgets('builds while trip planning is active', (tester) async {
    await di<TripAgentManager>().startPlanning(
      TripDraft.empty(
        id: 'draft-1',
        startLocation: const GeoCoordinate(lat: 48.4, lon: 9.99),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TripPlanningOverlay())),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Planning your trip'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FakeTripPlanningApiService extends TripPlanningApiService {
  _FakeTripPlanningApiService() : super(ApiClient(baseUrl: 'http://api.test'));

  final _controller = StreamController<TripPlanningEvent>.broadcast();

  @override
  Future<String> startSession(TripPlanningRequest request) async => 'session-1';

  @override
  Stream<TripPlanningEvent> watchEvents(String sessionId) => _controller.stream;

  Future<void> close() => _controller.close();
}
