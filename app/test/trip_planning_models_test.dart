import 'package:flutter_test/flutter_test.dart';
import 'package:meander/_shared/models/geo_coordinate.dart';
import 'package:meander/_shared/models/transport_mode.dart';
import 'package:meander/_shared/services/api_client.dart';
import 'package:meander/features/trip_planning/model/itinerary_step_draft.dart';
import 'package:meander/features/trip_planning/model/location_constraint.dart';
import 'package:meander/features/trip_planning/model/pending_trip_location_pick.dart';
import 'package:meander/features/trip_planning/model/time_constraint.dart';
import 'package:meander/features/trip_planning/model/trip_planning_session.dart';

void main() {
  test('serializes and parses itinerary draft steps', () {
    final step = ItineraryStepDraft.create(
      id: 'step-1',
      type: ItineraryStepType.meander,
      details: 'mixed afternoon',
      time: TimeConstraint(
        startTime: DateTime.parse('2026-06-06T15:00:00+02:00'),
        durationMinutes: 150,
      ),
      location: LocationConstraint.wherever(maxTransportMinutes: 20),
    );

    final parsed = ItineraryStepDraft.fromJson(step.toJson());

    expect(parsed.type, ItineraryStepType.meander);
    expect(parsed.type.detailHint, contains('mixed'));
    expect(parsed.location.type, LocationConstraintType.wherever);
    expect(parsed.location.maxTransportMinutes, 20);
    expect(parsed.time.durationMinutes, 150);
  });

  test('serializes trip planning request with transport modes', () {
    final request = TripPlanningRequest(
      draftId: 'draft-1',
      startLocation: const GeoCoordinate(lat: 48.4, lon: 9.99),
      transportModes: const [TransportMode.walk, TransportMode.publicTransport],
      steps: [
        ItineraryStepDraft.create(
          id: 'step-1',
          type: ItineraryStepType.sightsee,
          details: 'views',
          time: const TimeConstraint(durationMinutes: 45),
          location: LocationConstraint.aroundPoint(
            const GeoCoordinate(lat: 48.41, lon: 10),
          ),
        ),
      ],
    );

    expect(request.toJson(), {
      'draftId': 'draft-1',
      'startLocation': {'lat': 48.4, 'lon': 9.99},
      'transportModes': ['walk', 'publicTransport'],
      'steps': [
        {
          'id': 'step-1',
          'type': 'sightsee',
          'title': 'Sightsee',
          'details': 'views',
          'time': {'durationMinutes': 45},
          'location': {
            'type': 'aroundPoint',
            'point': {'lat': 48.41, 'lon': 10.0},
          },
          'iconKey': 'photo_camera',
          'colorValue': ItineraryStepType.sightsee.colorValue,
        },
      ],
    });
  });

  test('keeps pending trip location pick as transient app state', () {
    const pending = PendingTripLocationPick(
      type: ItineraryStepType.shop,
      details: 'clothes',
      durationMinutes: 90,
      insertIndex: 1,
      kind: TripLocationPickKind.areaCircle,
    );

    final updated = pending.copyWith(
      areaCenter: const GeoCoordinate(lat: 48.4, lon: 9.99),
      radiusMeters: 800,
    );

    expect(updated.kind.usesArea, isTrue);
    expect(updated.areaCenter!.lon, 9.99);
    expect(updated.radiusMeters, 800);
  });

  test('parses SSE question event', () {
    final event = TripPlanningEvent.fromSse(
      const ServerSentEvent(
        type: 'question',
        data: {
          'question': {
            'id': 'q1',
            'kind': 'yesNo',
            'prompt': 'Is walking for 18 min fine?',
          },
        },
      ),
    );

    expect(event.type, TripPlanningEventType.question);
    expect(event.question!.kind, TripPlanningQuestionKind.yesNo);
    expect(event.question!.prompt, contains('walking'));
  });
}
