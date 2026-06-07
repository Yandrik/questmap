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

  testWidgets('selection questions submit multiple selected options', (
    tester,
  ) async {
    await di<TripAgentManager>().startPlanning(
      TripDraft.empty(
        id: 'draft-1',
        startLocation: const GeoCoordinate(lat: 48.4, lon: 9.99),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TripPlanningOverlay())),
    );

    api.emit(
      TripPlanningEvent(
        type: TripPlanningEventType.question,
        question: const TripPlanningQuestion(
          id: 'q1',
          kind: TripPlanningQuestionKind.selection,
          prompt: 'Choose stops',
          options: [
            TripQuestionOption(id: 'rice-house', title: 'Rice House'),
            TripQuestionOption(id: 'museum', title: 'Museum'),
          ],
        ),
      ),
    );
    await tester.pump();

    var submitButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Submit'),
    );
    expect(submitButton.onPressed, isNull);
    expect(find.text('Choose at least one'), findsOneWidget);

    await tester.tap(find.text('Rice House'));
    await tester.pump();

    submitButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Submit'),
    );
    expect(submitButton.onPressed, isNotNull);
    expect(find.text('Choose at least one'), findsNothing);

    await tester.tap(find.text('Museum'));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Submit 2'));
    await tester.pump();

    expect(api.lastAnswer!.questionId, 'q1');
    expect(api.lastAnswer!.value, ['rice-house', 'museum']);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('selection questions scroll when options exceed viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await di<TripAgentManager>().startPlanning(
      TripDraft.empty(
        id: 'draft-1',
        startLocation: const GeoCoordinate(lat: 48.4, lon: 9.99),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TripPlanningOverlay())),
    );

    api.emit(
      TripPlanningEvent(
        type: TripPlanningEventType.question,
        question: TripPlanningQuestion(
          id: 'q1',
          kind: TripPlanningQuestionKind.selection,
          prompt: 'Choose stops',
          options: List.generate(
            24,
            (index) =>
                TripQuestionOption(id: 'stop-$index', title: 'Stop $index'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('Stop 23'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Stop 23'));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Submit'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pump();

    expect(api.lastAnswer!.value, ['stop-23']);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FakeTripPlanningApiService extends TripPlanningApiService {
  _FakeTripPlanningApiService() : super(ApiClient(baseUrl: 'http://api.test'));

  final _controller = StreamController<TripPlanningEvent>.broadcast();
  TripPlanningAnswer? lastAnswer;

  @override
  Future<String> startSession(TripPlanningRequest request) async => 'session-1';

  @override
  Stream<TripPlanningEvent> watchEvents(String sessionId) => _controller.stream;

  @override
  Future<void> answerQuestion({
    required String sessionId,
    required TripPlanningAnswer answer,
  }) async {
    lastAnswer = answer;
  }

  void emit(TripPlanningEvent event) {
    _controller.add(event);
  }

  Future<void> close() => _controller.close();
}
