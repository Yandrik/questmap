import 'package:flutter_test/flutter_test.dart';
import 'package:meander/_shared/models/geo_coordinate.dart';
import 'package:meander/_shared/models/transport_mode.dart';
import 'package:meander/_shared/services/api_client.dart';
import 'package:meander/features/trip_planning/model/itinerary_step_draft.dart';
import 'package:meander/features/trip_planning/model/location_constraint.dart';
import 'package:meander/features/trip_planning/model/pending_trip_location_pick.dart';
import 'package:meander/features/trip_planning/model/time_constraint.dart';
import 'package:meander/features/trip_planning/model/trip_plan.dart';
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

    final before = DateTime.now().toUtc();
    final json = request.toJson();
    final after = DateTime.now().toUtc();
    final steps = json['steps'] as List<Object?>;
    final firstStep = steps.single as Map<String, Object?>;
    final firstTime = firstStep['time'] as Map<String, Object?>;
    final startTime = DateTime.parse(firstTime['startTime'] as String);

    expect(startTime.isBefore(before), isFalse);
    expect(startTime.isAfter(after), isFalse);
    expect(json, {
      'draftId': 'draft-1',
      'startLocation': {'lat': 48.4, 'lon': 9.99},
      'transportModes': ['walk', 'publicTransport'],
      'steps': [
        {
          'id': 'step-1',
          'type': 'sightsee',
          'title': 'Sightsee',
          'details': 'views',
          'time': {'startTime': firstTime['startTime'], 'durationMinutes': 45},
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

  test('keeps explicit first step start time when serializing request', () {
    final explicitStart = DateTime.parse('2026-06-06T15:00:00Z');
    final request = TripPlanningRequest(
      draftId: 'draft-1',
      startLocation: const GeoCoordinate(lat: 48.4, lon: 9.99),
      transportModes: const [TransportMode.walk],
      steps: [
        ItineraryStepDraft.create(
          id: 'step-1',
          type: ItineraryStepType.eat,
          details: 'lunch',
          time: TimeConstraint(startTime: explicitStart, durationMinutes: 45),
          location: LocationConstraint.wherever(),
        ),
      ],
    );

    final json = request.toJson();
    final steps = json['steps'] as List<Object?>;
    final firstStep = steps.single as Map<String, Object?>;
    final firstTime = firstStep['time'] as Map<String, Object?>;

    expect(firstTime['startTime'], explicitStart.toIso8601String());
  });

  test('parses old and extended trip plans', () {
    final oldPlan = TripPlan.fromJson(const {
      'id': 'plan-old',
      'title': 'Old plan',
      'items': [
        {
          'id': 'travel-1',
          'type': 'travel',
          'title': 'Travel',
          'description': 'Walk there',
          'transportMode': 'walk',
          'geometry': [
            {'lat': 48.4, 'lon': 9.99},
            {'lat': 48.401, 'lon': 9.991},
          ],
        },
      ],
    });

    expect(oldPlan.items.single.segments, isEmpty);
    expect(oldPlan.items.single.geometry, hasLength(2));

    final extendedPlan = TripPlan.fromJson(const {
      'id': 'plan-new',
      'title': 'New plan',
      'items': [
        {
          'id': 'activity-1',
          'type': 'activity',
          'title': 'Shop',
          'description': 'books',
          'stepType': 'shop',
          'location': {'lat': 48.401, 'lon': 9.991, 'label': 'Book shop'},
          'visualTarget': {
            'type': 'areaCircle',
            'center': {'lat': 48.4, 'lon': 9.99},
            'radiusMeters': 800,
          },
        },
        {
          'id': 'travel-2',
          'type': 'travel',
          'title': 'Transit',
          'description': 'Bus',
          'transportMode': 'publicTransport',
          'segments': [
            {
              'transportMode': 'walk',
              'description': 'Walk',
              'transitDetails': {
                'fromLabel': 'Here',
                'toLabel': 'Stop A',
                'instructions': ['Continue for 80 m'],
              },
              'geometry': [
                {'lat': 48.4, 'lon': 9.99},
                {'lat': 48.401, 'lon': 9.991},
              ],
            },
          ],
        },
      ],
    });

    expect(
      extendedPlan.items.first.visualTarget!.type,
      LocationConstraintType.areaCircle,
    );
    expect(extendedPlan.items.first.visualTarget!.radiusMeters, 800);
    expect(
      extendedPlan.items.last.segments.single.transportMode,
      TransportMode.walk,
    );
    expect(
      extendedPlan.items.last.segments.single.transitDetails!.toLabel,
      'Stop A',
    );
    expect(extendedPlan.toJson()['items'], isA<List<Object?>>());
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
