import 'package:flutter_test/flutter_test.dart';
import 'package:meander/_shared/models/transport_mode.dart';
import 'package:meander/features/routing/model/navigation_candidate.dart';

void main() {
  test('parses Valhalla primary route and alternates', () {
    final candidates = NavigationCandidateParser.fromValhalla(
      mode: TransportMode.walk,
      json: {
        'trip': {
          'summary': {'length': 1.2, 'time': 840},
          'shape': {
            'type': 'LineString',
            'coordinates': [
              [9.99, 48.4],
              [10.0, 48.5],
            ],
          },
        },
        'alternates': [
          {
            'trip': {
              'summary': {'length': 1.5, 'time': 960},
              'shape': {
                'type': 'LineString',
                'coordinates': [
                  [9.98, 48.39],
                  [10.0, 48.5],
                ],
              },
            },
          },
        ],
      },
    );

    expect(candidates, hasLength(2));
    expect(candidates.first.mode, TransportMode.walk);
    expect(candidates.first.distanceMeters, 1200);
    expect(candidates.first.durationSeconds, 840);
    expect(candidates.first.geometry.first.lat, 48.4);
    expect(candidates.last.summaryLabel, '1.5 km · 16 min');
  });

  test('parses MOTIS itineraries as public transport alternatives', () {
    final candidates = NavigationCandidateParser.fromMotis({
      'itineraries': [
        {
          'id': 'itinerary-1',
          'duration': 1320,
          'legs': [
            {
              'mode': 'WALK',
              'from': {'name': 'Here'},
              'to': {'name': 'Stop A'},
              'duration': 240,
              'distance': 180,
            },
            {
              'mode': 'TRAM',
              'from': {'name': 'Stop A'},
              'to': {'name': 'Stop B'},
              'duration': 900,
              'displayName': 'Tram 2',
            },
          ],
        },
      ],
    });

    expect(candidates, hasLength(1));
    expect(candidates.single.mode, TransportMode.publicTransport);
    expect(candidates.single.summaryLabel, 'Tram 2 · 22 min');
    expect(candidates.single.legs.first.mode, TransportMode.walk);
    expect(candidates.single.legs.last.mode, TransportMode.publicTransport);
  });

  test('decodes Google polyline geometry', () {
    final coordinates = NavigationCandidateParser.decodePolyline(
      '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
      precision: 5,
    );

    expect(coordinates, hasLength(3));
    expect(coordinates.first.lat, 38.5);
    expect(coordinates.first.lon, -120.2);
    expect(coordinates.last.lat, 43.252);
    expect(coordinates.last.lon, -126.453);
  });
}
