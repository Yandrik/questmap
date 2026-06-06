import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meander/_shared/models/geo_coordinate.dart';
import 'package:meander/_shared/models/transport_mode.dart';
import 'package:meander/_shared/services/local_database.dart';
import 'package:meander/_shared/services/local_persistence_service.dart';
import 'package:meander/features/trip_planning/manager/trip_draft_manager.dart';
import 'package:meander/features/trip_planning/model/itinerary_step_draft.dart';
import 'package:meander/features/trip_planning/model/location_constraint.dart';
import 'package:meander/features/trip_planning/model/pending_trip_location_pick.dart';

void main() {
  late LocalDatabase database;
  late LocalPersistenceService persistence;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    persistence = LocalPersistenceService(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('creates, edits, saves, and restores active draft', () async {
    final manager = TripDraftManager(persistence);
    await manager.ensureDraft(
      startLocation: const GeoCoordinate(lat: 48.4, lon: 9.99),
    );

    manager.toggleTransportMode(TransportMode.bike);
    manager.addStep(
      type: ItineraryStepType.shop,
      details: 'clothes',
      durationMinutes: 90,
      location: LocationConstraint.wherever(maxTransportMinutes: 20),
    );
    await manager.saveNow();

    expect(manager.draft!.transportModes, contains(TransportMode.bike));
    expect(manager.draft!.steps.single.details, 'clothes');

    final restored = TripDraftManager(persistence);
    await restored.ensureDraft(
      startLocation: const GeoCoordinate(lat: 0, lon: 0),
    );

    expect(restored.draft!.startLocation.lat, 48.4);
    expect(restored.draft!.steps.single.type, ItineraryStepType.shop);
    expect(restored.draft!.steps.single.time.durationMinutes, 90);
  });

  test('inserts steps at any index and appends through addStep', () async {
    final manager = TripDraftManager(persistence);
    await manager.ensureDraft(
      startLocation: const GeoCoordinate(lat: 48.4, lon: 9.99),
    );

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
    manager.insertStep(
      index: 1,
      type: ItineraryStepType.sightsee,
      details: 'views',
      durationMinutes: 45,
      location: LocationConstraint.wherever(),
    );
    manager.insertStep(
      index: 99,
      type: ItineraryStepType.party,
      details: 'clubs',
      location: LocationConstraint.wherever(),
    );
    await manager.saveNow();

    expect(manager.draft!.steps.map((step) => step.type), [
      ItineraryStepType.shop,
      ItineraryStepType.sightsee,
      ItineraryStepType.eat,
      ItineraryStepType.party,
    ]);
    expect(manager.draft!.steps[1].time.durationMinutes, 45);

    final restored = TripDraftManager(persistence);
    await restored.ensureDraft(
      startLocation: const GeoCoordinate(lat: 0, lon: 0),
    );
    expect(restored.draft!.steps[1].details, 'views');
  });

  test('completes pending point location pick as inserted step', () async {
    final manager = TripDraftManager(persistence);
    await manager.ensureDraft(
      startLocation: const GeoCoordinate(lat: 48.4, lon: 9.99),
    );

    manager.beginLocationPick(
      index: 0,
      type: ItineraryStepType.exactLocation,
      details: 'minster',
      durationMinutes: 40,
      kind: TripLocationPickKind.exactPoint,
    );

    expect(manager.pendingLocationPick!.kind, TripLocationPickKind.exactPoint);

    manager.completePointPick(
      const GeoCoordinate(lat: 48.398, lon: 9.992, label: 'Ulmer Münster'),
    );

    expect(manager.pendingLocationPick, isNull);
    expect(manager.draft!.steps.single.type, ItineraryStepType.exactLocation);
    expect(
      manager.draft!.steps.single.location.type,
      LocationConstraintType.exactPoint,
    );
    expect(manager.draft!.steps.single.location.point!.label, 'Ulmer Münster');
  });

  test('completes pending area location pick with radius', () async {
    final manager = TripDraftManager(persistence);
    await manager.ensureDraft(
      startLocation: const GeoCoordinate(lat: 48.4, lon: 9.99),
    );

    manager.beginLocationPick(
      index: 0,
      type: ItineraryStepType.shop,
      details: 'clothes',
      durationMinutes: 90,
      kind: TripLocationPickKind.areaCircle,
    );
    manager.updatePendingAreaRadius(800);
    manager.completeAreaPick(
      center: const GeoCoordinate(lat: 48.401, lon: 9.991),
      radiusMeters: manager.pendingLocationPick!.radiusMeters,
    );

    final location = manager.draft!.steps.single.location;
    expect(location.type, LocationConstraintType.areaCircle);
    expect(location.center!.lat, 48.401);
    expect(location.radiusMeters, 800);
  });

  test('cancels pending location pick without changing draft', () async {
    final manager = TripDraftManager(persistence);
    await manager.ensureDraft(
      startLocation: const GeoCoordinate(lat: 48.4, lon: 9.99),
    );

    manager.beginLocationPick(
      index: 0,
      type: ItineraryStepType.walk,
      details: 'parks',
      durationMinutes: 60,
      kind: TripLocationPickKind.aroundPoint,
    );
    manager.cancelLocationPick();

    expect(manager.pendingLocationPick, isNull);
    expect(manager.draft!.steps, isEmpty);
  });
}
