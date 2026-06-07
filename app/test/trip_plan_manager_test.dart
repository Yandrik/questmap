import 'package:flutter_test/flutter_test.dart';
import 'package:meander/_shared/models/geo_coordinate.dart';
import 'package:meander/_shared/models/transport_mode.dart';
import 'package:meander/_shared/services/local_persistence_service.dart';
import 'package:meander/features/trip_planning/manager/trip_plan_manager.dart';
import 'package:meander/features/trip_planning/model/itinerary_step_draft.dart';
import 'package:meander/features/trip_planning/model/trip_plan.dart';

void main() {
  late LocalPersistenceService persistence;

  setUp(() {
    persistence = LocalPersistenceService(MemoryLocalPersistenceStore());
  });

  test('rejects active plan and deletes persisted progress', () async {
    final manager = TripPlanManager(persistence);
    await manager.setPlan(_plan());
    manager.startTrip();
    await Future<void>.delayed(Duration.zero);

    await manager.rejectPlan();

    expect(manager.currentPlan, isNull);
    expect(manager.isTripActive, isFalse);

    final restored = TripPlanManager(persistence);
    await restored.loadActivePlan();
    expect(restored.currentPlan, isNull);
    expect(restored.completedItemIds, isEmpty);
  });

  test('starts trip with first item and restores active progress', () async {
    final manager = TripPlanManager(persistence);
    await manager.setPlan(_plan());

    manager.startTrip();
    await Future<void>.delayed(Duration.zero);

    expect(manager.isTripActive, isTrue);
    expect(manager.currentItemId, 'travel-1');
    expect(manager.currentItem!.type, TripPlanItemType.travel);

    final restored = TripPlanManager(persistence);
    await restored.loadActivePlan();
    expect(restored.isTripActive, isTrue);
    expect(restored.currentItemId, 'travel-1');
  });

  test('auto-arrival starts activity timer and completion ends trip', () async {
    final manager = TripPlanManager(persistence);
    await manager.setPlan(_plan());
    manager.startTrip();

    final advanced = manager.maybeMarkArrived(
      const GeoCoordinate(lat: 48.401, lon: 9.991),
    );

    expect(advanced, isTrue);
    expect(manager.completedItemIds, contains('travel-1'));
    expect(manager.currentItemId, 'activity-1');
    expect(manager.activeActivityStartedAt, isNotNull);

    final completed = manager.completeCurrentActivity();

    expect(completed, isTrue);
    expect(manager.completedItemIds, contains('activity-1'));
    expect(manager.isTripActive, isFalse);
    expect(manager.currentItem, isNull);
  });

  test('does not auto-arrive outside threshold', () async {
    final manager = TripPlanManager(persistence);
    await manager.setPlan(_plan());
    manager.startTrip();

    final advanced = manager.maybeMarkArrived(
      const GeoCoordinate(lat: 48.45, lon: 10.05),
    );

    expect(advanced, isFalse);
    expect(manager.currentItemId, 'travel-1');
  });
}

TripPlan _plan() {
  final start = DateTime.parse('2026-06-07T10:00:00Z');
  return TripPlan(
    id: 'plan-1',
    title: 'Trip',
    items: [
      TripPlanItem(
        id: 'travel-1',
        type: TripPlanItemType.travel,
        title: 'Travel to Shop',
        description: 'Walk, about 5 min.',
        transportMode: TransportMode.walk,
        startTime: start,
        endTime: start.add(const Duration(minutes: 5)),
        geometry: const [
          GeoCoordinate(lat: 48.4, lon: 9.99),
          GeoCoordinate(lat: 48.401, lon: 9.991),
        ],
      ),
      TripPlanItem(
        id: 'activity-1',
        type: TripPlanItemType.activity,
        title: 'Shop',
        description: 'books',
        stepType: ItineraryStepType.shop,
        startTime: start.add(const Duration(minutes: 5)),
        endTime: start.add(const Duration(minutes: 35)),
        location: const GeoCoordinate(
          lat: 48.401,
          lon: 9.991,
          label: 'Book shop',
        ),
      ),
    ],
  );
}
