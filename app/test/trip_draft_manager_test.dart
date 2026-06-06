import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meander/_shared/models/geo_coordinate.dart';
import 'package:meander/_shared/models/transport_mode.dart';
import 'package:meander/_shared/services/local_database.dart';
import 'package:meander/_shared/services/local_persistence_service.dart';
import 'package:meander/features/trip_planning/manager/trip_draft_manager.dart';
import 'package:meander/features/trip_planning/model/itinerary_step_draft.dart';
import 'package:meander/features/trip_planning/model/location_constraint.dart';

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
}
