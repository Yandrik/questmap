import 'package:flutter_test/flutter_test.dart';
import 'package:meander/features/transit/model/motis_plan_request.dart';

void main() {
  test('serializes a plan request using MOTIS OpenAPI query names', () {
    final request = MotisPlanRequest(
      fromPlace: '48.7758,9.1829',
      toPlace: '48.3984,9.9916',
      time: DateTime.parse('2026-06-06T14:00:00+02:00'),
      transitModes: const [MotisMode.transit],
      directModes: const [],
      preTransitModes: const [MotisMode.walk],
      postTransitModes: const [MotisMode.walk],
      pedestrianProfile: MotisPedestrianProfile.foot,
      elevationCosts: MotisElevationCosts.none,
      timetableView: true,
      language: const ['de', 'en'],
      algorithm: MotisAlgorithm.pong,
    );

    expect(request.toQueryParameters(), {
      'fromPlace': '48.7758,9.1829',
      'toPlace': '48.3984,9.9916',
      'time': '2026-06-06T12:00:00.000Z',
      'pedestrianProfile': 'FOOT',
      'elevationCosts': 'NONE',
      'transitModes': 'TRANSIT',
      'directModes': '',
      'preTransitModes': 'WALK',
      'postTransitModes': 'WALK',
      'timetableView': true,
      'language': 'de,en',
      'algorithm': 'PONG',
    });
  });
}
