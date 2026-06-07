import 'package:flutter_test/flutter_test.dart';
import 'package:meander/_shared/models/geo_coordinate.dart';
import 'package:meander/_shared/models/transport_mode.dart';
import 'package:meander/features/map/services/map_route_overlay.dart';
import 'package:meander/features/routing/model/navigation_candidate.dart';

void main() {
  test('builds selected public transport route as colored leg features', () {
    const candidate = NavigationCandidate(
      id: 'transit-1',
      mode: TransportMode.publicTransport,
      durationSeconds: 900,
      summaryLabel: 'Bus 7 · 15 min',
      geometry: [
        GeoCoordinate(lat: 48.4, lon: 9.99),
        GeoCoordinate(lat: 48.41, lon: 10),
      ],
      legs: [
        NavigationLeg(
          mode: TransportMode.walk,
          fromLabel: 'Here',
          toLabel: 'Stop A',
          durationSeconds: 120,
          geometry: [
            GeoCoordinate(lat: 48.4, lon: 9.99),
            GeoCoordinate(lat: 48.401, lon: 9.991),
          ],
        ),
        NavigationLeg(
          mode: TransportMode.publicTransport,
          fromLabel: 'Stop A',
          toLabel: 'Stop B',
          durationSeconds: 780,
          geometry: [
            GeoCoordinate(lat: 48.401, lon: 9.991),
            GeoCoordinate(lat: 48.41, lon: 10),
          ],
        ),
      ],
    );

    final geoJson = MapRouteOverlayGeoJson.selected(candidate);
    final features = geoJson['features'] as List<Object?>;

    expect(features, hasLength(2));
    expect(_properties(features.first)['color'], '#22c55e');
    expect(_properties(features.last)['color'], '#a855f7');
    expect(_properties(features.first)['transportMode'], 'walk');
    expect(_properties(features.last)['transportMode'], 'publicTransport');
  });

  test('falls back to single selected route feature without leg geometry', () {
    const candidate = NavigationCandidate(
      id: 'route-1',
      mode: TransportMode.drive,
      durationSeconds: 600,
      summaryLabel: '10 min',
      geometry: [
        GeoCoordinate(lat: 48.4, lon: 9.99),
        GeoCoordinate(lat: 48.41, lon: 10),
      ],
    );

    final geoJson = MapRouteOverlayGeoJson.selected(candidate);
    final features = geoJson['features'] as List<Object?>;

    expect(features, hasLength(1));
    expect(_properties(features.single)['color'], '#2563eb');
  });
}

Map<String, Object?> _properties(Object? feature) {
  final map = feature as Map<String, Object?>;
  return map['properties'] as Map<String, Object?>;
}
