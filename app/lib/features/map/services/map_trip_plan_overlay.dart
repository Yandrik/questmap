import 'dart:math' as math;

import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../_shared/models/geo_coordinate.dart';
import '../../../_shared/models/transport_mode.dart';
import '../../trip_planning/model/itinerary_step_draft.dart';
import '../../trip_planning/model/location_constraint.dart';
import '../../trip_planning/model/trip_plan.dart';
import 'map_style_config.dart';

class MapTripPlanOverlay {
  bool _layersReady = false;

  Future<void> addTripPlanLayers(MapLibreMapController controller) async {
    _layersReady = false;
    await controller.addGeoJsonSource(
      MapStyleConfig.tripRouteCompletedSourceId,
      TripPlanOverlayGeoJson.emptyFeatureCollection(),
    );
    await controller.addLineLayer(
      MapStyleConfig.tripRouteCompletedSourceId,
      MapStyleConfig.tripRouteCompletedLayerId,
      const LineLayerProperties(
        lineColor: '#94a3b8',
        lineOpacity: 0.48,
        lineWidth: 5,
      ),
      belowLayerId: MapStyleConfig.selectionLayerId,
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(
      MapStyleConfig.tripRouteFutureSourceId,
      TripPlanOverlayGeoJson.emptyFeatureCollection(),
    );
    await controller.addLineLayer(
      MapStyleConfig.tripRouteFutureSourceId,
      MapStyleConfig.tripRouteFutureLayerId,
      const LineLayerProperties(
        lineColor: ['get', 'color'],
        lineOpacity: 0.72,
        lineWidth: 4,
      ),
      belowLayerId: MapStyleConfig.selectionLayerId,
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(
      MapStyleConfig.tripRouteActiveSourceId,
      TripPlanOverlayGeoJson.emptyFeatureCollection(),
    );
    await controller.addLineLayer(
      MapStyleConfig.tripRouteActiveSourceId,
      MapStyleConfig.tripRouteActiveLayerId,
      const LineLayerProperties(
        lineColor: '#2563eb',
        lineOpacity: 0.94,
        lineWidth: 7,
      ),
      belowLayerId: MapStyleConfig.selectionLayerId,
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(
      MapStyleConfig.tripActivityAreaSourceId,
      TripPlanOverlayGeoJson.emptyFeatureCollection(),
    );
    await controller.addFillLayer(
      MapStyleConfig.tripActivityAreaSourceId,
      MapStyleConfig.tripActivityAreaFillLayerId,
      const FillLayerProperties(fillColor: ['get', 'color'], fillOpacity: 0.17),
      belowLayerId: MapStyleConfig.selectionLayerId,
      enableInteraction: false,
    );
    await controller.addLineLayer(
      MapStyleConfig.tripActivityAreaSourceId,
      MapStyleConfig.tripActivityAreaStrokeLayerId,
      const LineLayerProperties(
        lineColor: ['get', 'color'],
        lineOpacity: 0.9,
        lineWidth: 2,
      ),
      belowLayerId: MapStyleConfig.selectionLayerId,
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(
      MapStyleConfig.tripActivityPointSourceId,
      TripPlanOverlayGeoJson.emptyFeatureCollection(),
    );
    await controller.addCircleLayer(
      MapStyleConfig.tripActivityPointSourceId,
      MapStyleConfig.tripActivityPointLayerId,
      const CircleLayerProperties(
        circleRadius: 8,
        circleColor: ['get', 'color'],
        circleOpacity: 0.86,
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
      ),
      belowLayerId: MapStyleConfig.selectionLayerId,
      enableInteraction: false,
    );

    _layersReady = true;
  }

  Future<void> setTripPlan({
    required MapLibreMapController controller,
    required TripPlan? plan,
    required Set<String> completedItemIds,
    required String? currentItemId,
    required bool isTripActive,
  }) async {
    if (!_layersReady) return;
    final geoJson = TripPlanOverlayGeoJson.build(
      plan: plan,
      completedItemIds: completedItemIds,
      currentItemId: currentItemId,
      isTripActive: isTripActive,
    );
    await controller.setGeoJsonSource(
      MapStyleConfig.tripRouteCompletedSourceId,
      geoJson.completedRoutes,
    );
    await controller.setGeoJsonSource(
      MapStyleConfig.tripRouteFutureSourceId,
      geoJson.futureRoutes,
    );
    await controller.setGeoJsonSource(
      MapStyleConfig.tripRouteActiveSourceId,
      geoJson.activeRoutes,
    );
    await controller.setGeoJsonSource(
      MapStyleConfig.tripActivityAreaSourceId,
      geoJson.activityAreas,
    );
    await controller.setGeoJsonSource(
      MapStyleConfig.tripActivityPointSourceId,
      geoJson.activityPoints,
    );
  }
}

class TripPlanOverlayGeoJson {
  const TripPlanOverlayGeoJson({
    required this.completedRoutes,
    required this.futureRoutes,
    required this.activeRoutes,
    required this.activityAreas,
    required this.activityPoints,
  });

  final Map<String, Object?> completedRoutes;
  final Map<String, Object?> futureRoutes;
  final Map<String, Object?> activeRoutes;
  final Map<String, Object?> activityAreas;
  final Map<String, Object?> activityPoints;

  static TripPlanOverlayGeoJson build({
    required TripPlan? plan,
    required Set<String> completedItemIds,
    required String? currentItemId,
    required bool isTripActive,
  }) {
    final completedRoutes = <Map<String, Object?>>[];
    final futureRoutes = <Map<String, Object?>>[];
    final activeRoutes = <Map<String, Object?>>[];
    final activityAreas = <Map<String, Object?>>[];
    final activityPoints = <Map<String, Object?>>[];
    final activeTravelId = _activeTravelId(plan, currentItemId, isTripActive);

    for (final item in plan?.items ?? const <TripPlanItem>[]) {
      if (item.type == TripPlanItemType.travel) {
        final features = _routeFeatures(item);
        if (completedItemIds.contains(item.id)) {
          completedRoutes.addAll(features);
        } else if (item.id == activeTravelId) {
          activeRoutes.addAll(features);
        } else {
          futureRoutes.addAll(features);
        }
        continue;
      }

      final color = _activityColor(item.stepType);
      final location = item.location;
      if (location != null) {
        activityPoints.add(_pointFeature(location, item.id, color));
      }
      final target = item.visualTarget;
      if (target?.type == LocationConstraintType.areaCircle &&
          target?.center != null) {
        activityAreas.add(
          _areaFeature(
            target!.center!,
            target.radiusMeters ?? 500,
            item.id,
            color,
          ),
        );
      }
    }

    return TripPlanOverlayGeoJson(
      completedRoutes: _featureCollection(completedRoutes),
      futureRoutes: _featureCollection(futureRoutes),
      activeRoutes: _featureCollection(activeRoutes),
      activityAreas: _featureCollection(activityAreas),
      activityPoints: _featureCollection(activityPoints),
    );
  }

  static Map<String, Object?> emptyFeatureCollection() {
    return _featureCollection(const []);
  }

  static String? _activeTravelId(
    TripPlan? plan,
    String? currentItemId,
    bool isTripActive,
  ) {
    if (!isTripActive || plan == null || currentItemId == null) return null;
    final currentIndex = plan.items.indexWhere(
      (item) => item.id == currentItemId,
    );
    if (currentIndex < 0) return null;
    final current = plan.items[currentIndex];
    if (current.type == TripPlanItemType.travel) return current.id;
    for (final item in plan.items.skip(currentIndex + 1)) {
      if (item.type == TripPlanItemType.travel) return item.id;
    }
    return null;
  }

  static List<Map<String, Object?>> _routeFeatures(TripPlanItem item) {
    if (item.segments.isEmpty) {
      return [
        _lineFeature(
          item.geometry,
          item.id,
          _modeColor(item.transportMode),
          item.transportMode,
        ),
      ];
    }
    return [
      for (var index = 0; index < item.segments.length; index++)
        _lineFeature(
          item.segments[index].geometry,
          '${item.id}-$index',
          _modeColor(item.segments[index].transportMode),
          item.segments[index].transportMode,
        ),
    ];
  }

  static Map<String, Object?> _lineFeature(
    List<GeoCoordinate> geometry,
    String id,
    String color,
    TransportMode? mode,
  ) {
    return {
      'type': 'Feature',
      'properties': {
        'id': id,
        'color': color,
        if (mode != null) 'transportMode': mode.apiValue,
      },
      'geometry': {
        'type': 'LineString',
        'coordinates': geometry
            .map((coordinate) => [coordinate.lon, coordinate.lat])
            .toList(),
      },
    };
  }

  static Map<String, Object?> _pointFeature(
    GeoCoordinate point,
    String id,
    String color,
  ) {
    return {
      'type': 'Feature',
      'properties': {'id': id, 'color': color},
      'geometry': {
        'type': 'Point',
        'coordinates': [point.lon, point.lat],
      },
    };
  }

  static Map<String, Object?> _areaFeature(
    GeoCoordinate center,
    double radiusMeters,
    String id,
    String color,
  ) {
    return {
      'type': 'Feature',
      'properties': {'id': id, 'color': color},
      'geometry': {
        'type': 'Polygon',
        'coordinates': [_circleCoordinates(center, radiusMeters)],
      },
    };
  }

  static Map<String, Object?> _featureCollection(
    List<Map<String, Object?>> features,
  ) {
    return {
      'type': 'FeatureCollection',
      'features': features.where((feature) {
        final geometry = feature['geometry'];
        if (geometry is! Map<String, Object?>) return true;
        if (geometry['type'] != 'LineString') return true;
        final coordinates = geometry['coordinates'];
        return coordinates is List && coordinates.length >= 2;
      }).toList(),
    };
  }

  static String _activityColor(ItineraryStepType? type) {
    final value = type?.colorValue ?? 0xFF14B8A6;
    return '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }

  static String _modeColor(TransportMode? mode) {
    return switch (mode) {
      TransportMode.walk => '#22c55e',
      TransportMode.bike => '#14b8a6',
      TransportMode.drive => '#f97316',
      TransportMode.publicTransport => '#a855f7',
      null => '#64748b',
    };
  }

  static List<List<double>> _circleCoordinates(
    GeoCoordinate center,
    double radiusMeters,
  ) {
    const earthRadiusMeters = 6378137.0;
    const segments = 72;
    final lat = _toRadians(center.lat);
    final lon = _toRadians(center.lon);
    final angularDistance = radiusMeters / earthRadiusMeters;

    return [
      for (var index = 0; index <= segments; index++)
        _destinationCoordinate(
          lat: lat,
          lon: lon,
          angularDistance: angularDistance,
          bearing: 2 * math.pi * index / segments,
        ),
    ];
  }

  static List<double> _destinationCoordinate({
    required double lat,
    required double lon,
    required double angularDistance,
    required double bearing,
  }) {
    final destinationLat = math.asin(
      math.sin(lat) * math.cos(angularDistance) +
          math.cos(lat) * math.sin(angularDistance) * math.cos(bearing),
    );
    final destinationLon =
        lon +
        math.atan2(
          math.sin(bearing) * math.sin(angularDistance) * math.cos(lat),
          math.cos(angularDistance) - math.sin(lat) * math.sin(destinationLat),
        );
    return [_toDegrees(destinationLon), _toDegrees(destinationLat)];
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
  static double _toDegrees(double radians) => radians * 180 / math.pi;
}
