import 'package:flutter_test/flutter_test.dart';
import 'package:meander/_shared/models/geo_coordinate.dart';
import 'package:meander/_shared/models/transport_mode.dart';
import 'package:meander/features/map/services/map_trip_plan_overlay.dart';
import 'package:meander/features/trip_planning/model/itinerary_step_draft.dart';
import 'package:meander/features/trip_planning/model/location_constraint.dart';
import 'package:meander/features/trip_planning/model/trip_plan.dart';

void main() {
  test('builds trip overlay geojson by progress and type colors', () {
    final geoJson = TripPlanOverlayGeoJson.build(
      plan: _plan(),
      completedItemIds: const {},
      currentItemId: 'travel-1',
      isTripActive: true,
    );

    expect(_features(geoJson.activeRoutes), hasLength(1));
    expect(_features(geoJson.futureRoutes), hasLength(2));
    expect(_features(geoJson.completedRoutes), isEmpty);
    expect(_features(geoJson.activityPoints), hasLength(1));
    expect(_features(geoJson.activityAreas), hasLength(1));

    final futureColors = _features(
      geoJson.futureRoutes,
    ).map((feature) => _properties(feature)['color']).toSet();
    expect(futureColors, contains('#22c55e'));
    expect(futureColors, contains('#a855f7'));
    expect(
      _properties(_features(geoJson.activityAreas).single)['color'],
      '#3b82f6',
    );
  });

  test('moves completed travel to muted route bucket', () {
    final geoJson = TripPlanOverlayGeoJson.build(
      plan: _plan(),
      completedItemIds: const {'travel-1'},
      currentItemId: 'activity-1',
      isTripActive: true,
    );

    expect(_features(geoJson.completedRoutes), hasLength(1));
    expect(_features(geoJson.activeRoutes), hasLength(2));
  });
}

TripPlan _plan() {
  return TripPlan(
    id: 'plan-1',
    title: 'Trip',
    items: [
      const TripPlanItem(
        id: 'travel-1',
        type: TripPlanItemType.travel,
        title: 'Travel to Shop',
        description: 'Walk',
        transportMode: TransportMode.walk,
        geometry: [
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
        location: const GeoCoordinate(lat: 48.401, lon: 9.991),
        visualTarget: LocationConstraint.areaCircle(
          center: const GeoCoordinate(lat: 48.401, lon: 9.991),
          radiusMeters: 800,
        ),
      ),
      const TripPlanItem(
        id: 'travel-2',
        type: TripPlanItemType.travel,
        title: 'Travel to Food',
        description: 'Transit',
        transportMode: TransportMode.publicTransport,
        segments: [
          TripRouteSegment(
            transportMode: TransportMode.walk,
            geometry: [
              GeoCoordinate(lat: 48.401, lon: 9.991),
              GeoCoordinate(lat: 48.402, lon: 9.992),
            ],
          ),
          TripRouteSegment(
            transportMode: TransportMode.publicTransport,
            geometry: [
              GeoCoordinate(lat: 48.402, lon: 9.992),
              GeoCoordinate(lat: 48.41, lon: 10),
            ],
          ),
        ],
      ),
    ],
  );
}

List<Object?> _features(Map<String, Object?> featureCollection) {
  return featureCollection['features'] as List<Object?>;
}

Map<String, Object?> _properties(Object? feature) {
  final map = feature as Map<String, Object?>;
  return map['properties'] as Map<String, Object?>;
}
