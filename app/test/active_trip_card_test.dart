import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_it/watch_it.dart';

import 'package:meander/_shared/models/geo_coordinate.dart';
import 'package:meander/_shared/models/transit_leg_details.dart';
import 'package:meander/_shared/models/transport_mode.dart';
import 'package:meander/_shared/services/local_persistence_service.dart';
import 'package:meander/features/trip_planning/manager/trip_plan_manager.dart';
import 'package:meander/features/trip_planning/model/itinerary_step_draft.dart';
import 'package:meander/features/trip_planning/model/location_constraint.dart';
import 'package:meander/features/trip_planning/model/trip_plan.dart';
import 'package:meander/features/trip_planning/widgets/active_trip_card.dart';

void main() {
  setUp(() async {
    await di.reset();
    di.registerLazySingleton<LocalPersistenceService>(
      () => LocalPersistenceService(MemoryLocalPersistenceStore()),
    );
    di.registerLazySingleton<TripPlanManager>(
      () => TripPlanManager(di<LocalPersistenceService>()),
      dispose: (manager) => manager.dispose(),
    );
    await di<TripPlanManager>().setPlan(_plan());
    di<TripPlanManager>().startTrip();
  });

  tearDown(() async {
    await di.reset();
  });

  testWidgets('shows travel then activity details and completes trip', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ActiveTripCard())),
    );
    await tester.pump();

    expect(find.text('Travel to Shop'), findsOneWidget);
    expect(find.text('Arrived'), findsOneWidget);

    await tester.tap(find.text('Arrived'));
    await tester.pump();

    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('books'), findsOneWidget);
    expect(find.textContaining('Area near'), findsOneWidget);
    expect(find.text('Complete'), findsOneWidget);

    await tester.tap(find.text('Complete'));
    await tester.pump();

    expect(di<TripPlanManager>().isTripActive, isFalse);
  });

  testWidgets('shows public transport segment itinerary details', (
    tester,
  ) async {
    await di<TripPlanManager>().setPlan(_transitPlan());
    di<TripPlanManager>().startTrip();

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ActiveTripCard())),
    );
    await tester.pump();

    expect(find.text('Travel to Museum'), findsOneWidget);
    expect(find.text('Walk to Stop A'), findsOneWidget);
    expect(
      find.text('Take Bus 7 toward Downtown from Stop A; get off at Stop B'),
      findsOneWidget,
    );
    expect(find.text('2 intermediate stops'), findsOneWidget);
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
        location: const GeoCoordinate(lat: 48.401, lon: 9.991),
        visualTarget: LocationConstraint.areaCircle(
          center: const GeoCoordinate(lat: 48.401, lon: 9.991),
          radiusMeters: 800,
        ),
      ),
    ],
  );
}

TripPlan _transitPlan() {
  final start = DateTime.parse('2026-06-07T10:00:00Z');
  return TripPlan(
    id: 'plan-transit',
    title: 'Transit trip',
    items: [
      TripPlanItem(
        id: 'travel-1',
        type: TripPlanItemType.travel,
        title: 'Travel to Museum',
        description: 'Bus 7, about 26 min.',
        transportMode: TransportMode.publicTransport,
        startTime: start,
        endTime: start.add(const Duration(minutes: 26)),
        segments: [
          const TripRouteSegment(
            transportMode: TransportMode.walk,
            description: 'Walk, about 4 min.',
            transitDetails: TransitLegDetails(
              fromLabel: 'Here',
              toLabel: 'Stop A',
            ),
          ),
          TripRouteSegment(
            transportMode: TransportMode.publicTransport,
            description: 'Bus 7, about 20 min.',
            transitDetails: TransitLegDetails(
              fromLabel: 'Stop A',
              toLabel: 'Stop B',
              displayName: '7',
              vehicleType: 'Bus',
              headsign: 'Downtown',
              startTime: start.add(const Duration(minutes: 5)),
              endTime: start.add(const Duration(minutes: 25)),
              realTime: true,
              intermediateStopLabels: const ['Middle A', 'Middle B'],
            ),
          ),
        ],
      ),
      TripPlanItem(
        id: 'activity-1',
        type: TripPlanItemType.activity,
        title: 'Museum',
        description: 'exhibits',
        stepType: ItineraryStepType.sightsee,
        startTime: start.add(const Duration(minutes: 26)),
        endTime: start.add(const Duration(minutes: 86)),
        location: const GeoCoordinate(lat: 48.401, lon: 9.991),
      ),
    ],
  );
}
