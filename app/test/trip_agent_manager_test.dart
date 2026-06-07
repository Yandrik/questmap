import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meander/_shared/models/geo_coordinate.dart';
import 'package:meander/_shared/models/transport_mode.dart';
import 'package:meander/_shared/services/api_client.dart';
import 'package:meander/_shared/services/local_persistence_service.dart';
import 'package:meander/features/trip_planning/manager/trip_agent_manager.dart';
import 'package:meander/features/trip_planning/manager/trip_plan_manager.dart';
import 'package:meander/features/trip_planning/model/itinerary_step_draft.dart';
import 'package:meander/features/trip_planning/model/location_constraint.dart';
import 'package:meander/features/trip_planning/model/time_constraint.dart';
import 'package:meander/features/trip_planning/model/trip_draft.dart';
import 'package:meander/features/trip_planning/model/trip_plan.dart';
import 'package:meander/features/trip_planning/model/trip_planning_session.dart';
import 'package:meander/features/trip_planning/services/trip_planning_api_service.dart';

void main() {
  late LocalPersistenceService persistence;
  late _FakeTripPlanningApiService api;
  late TripPlanManager planManager;
  late TripAgentManager agentManager;

  setUp(() {
    persistence = LocalPersistenceService(MemoryLocalPersistenceStore());
    api = _FakeTripPlanningApiService();
    planManager = TripPlanManager(persistence);
    agentManager = TripAgentManager(api, planManager, persistence);
  });

  tearDown(() async {
    agentManager.dispose();
    planManager.dispose();
    await api.close();
  });

  test('handles question, answer, and final plan events', () async {
    final draft =
        TripDraft.empty(
          id: 'draft-1',
          startLocation: const GeoCoordinate(lat: 48.4, lon: 9.99),
        ).copyWith(
          transportModes: const {TransportMode.walk},
          steps: [
            ItineraryStepDraft.create(
              id: 'step-1',
              type: ItineraryStepType.eat,
              details: 'Chinese',
              time: const TimeConstraint(durationMinutes: 60),
              location: LocationConstraint.wherever(),
            ),
          ],
        );

    await agentManager.startPlanning(draft);
    expect(agentManager.isPlanning, isTrue);
    expect(api.lastRequest!.steps.single.details, 'Chinese');

    api.emit(
      TripPlanningEvent(
        type: TripPlanningEventType.question,
        question: const TripPlanningQuestion(
          id: 'q1',
          kind: TripPlanningQuestionKind.yesNo,
          prompt: 'Is walking 12 min fine?',
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(agentManager.question!.id, 'q1');

    await agentManager.answerQuestion(true);
    expect(api.lastAnswer!.value, true);
    expect(agentManager.question, isNull);

    api.emit(
      const TripPlanningEvent(
        type: TripPlanningEventType.finalPlan,
        plan: TripPlan(
          id: 'plan-1',
          title: 'Dinner plan',
          items: [
            TripPlanItem(
              id: 'item-1',
              type: TripPlanItemType.activity,
              title: 'Eat',
              description: 'Good Chinese food',
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(agentManager.isPlanning, isFalse);
    expect(planManager.currentPlan!.id, 'plan-1');

    planManager.startTrip();
    planManager.toggleItemDone('item-1');

    final restored = TripPlanManager(persistence);
    await restored.loadActivePlan();
    expect(restored.currentPlan!.title, 'Dinner plan');
    expect(restored.completedItemIds, contains('item-1'));
    expect(restored.isTripActive, isTrue);
  });

  test('reconnects event stream when it closes while planning', () async {
    final draft =
        TripDraft.empty(
          id: 'draft-1',
          startLocation: const GeoCoordinate(lat: 48.4, lon: 9.99),
        ).copyWith(
          transportModes: const {TransportMode.walk},
          steps: [
            ItineraryStepDraft.create(
              id: 'step-1',
              type: ItineraryStepType.shop,
              details: 'gifts',
              time: const TimeConstraint(durationMinutes: 45),
              location: LocationConstraint.wherever(),
            ),
          ],
        );

    await agentManager.startPlanning(draft);
    expect(api.watchEventsCount, 1);

    api.emit(
      const TripPlanningEvent(
        type: TripPlanningEventType.status,
        message: 'Finding places near your route...',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await api.closeCurrentStream();

    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(api.watchEventsCount, 2);

    api.emit(
      TripPlanningEvent(
        type: TripPlanningEventType.question,
        question: const TripPlanningQuestion(
          id: 'q1',
          kind: TripPlanningQuestionKind.selection,
          prompt: 'Choose a shop',
          options: [TripQuestionOption(id: 'shop-1', title: 'Gift Shop')],
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(agentManager.question!.id, 'q1');
    await agentManager.answerQuestion(['shop-1']);
    expect(api.lastAnswer!.questionId, 'q1');
    expect(api.lastAnswer!.value, ['shop-1']);
  });
}

class _FakeTripPlanningApiService extends TripPlanningApiService {
  _FakeTripPlanningApiService() : super(ApiClient(baseUrl: 'http://api.test'));

  final _controllers = <StreamController<TripPlanningEvent>>[];
  TripPlanningRequest? lastRequest;
  TripPlanningAnswer? lastAnswer;
  bool cancelled = false;
  int watchEventsCount = 0;

  @override
  Future<String> startSession(TripPlanningRequest request) async {
    lastRequest = request;
    return 'session-1';
  }

  @override
  Stream<TripPlanningEvent> watchEvents(String sessionId) {
    watchEventsCount++;
    final controller = StreamController<TripPlanningEvent>.broadcast();
    _controllers.add(controller);
    return controller.stream;
  }

  @override
  Future<void> answerQuestion({
    required String sessionId,
    required TripPlanningAnswer answer,
  }) async {
    lastAnswer = answer;
  }

  @override
  Future<void> cancelSession(String sessionId) async {
    cancelled = true;
  }

  void emit(TripPlanningEvent event) {
    _controllers.last.add(event);
  }

  Future<void> closeCurrentStream() => _controllers.last.close();

  Future<void> close() async {
    for (final controller in _controllers) {
      await controller.close();
    }
  }
}
