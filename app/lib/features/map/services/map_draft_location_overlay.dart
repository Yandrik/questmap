import 'dart:math' as math;

import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../_shared/models/geo_coordinate.dart';
import 'map_style_config.dart';

class MapDraftLocationOverlay {
  bool _layersReady = false;

  Future<void> addDraftLocationLayers(MapLibreMapController controller) async {
    _layersReady = false;
    await controller.addGeoJsonSource(
      MapStyleConfig.draftLocationAreaSourceId,
      _featureCollection(const []),
    );
    await controller.addFillLayer(
      MapStyleConfig.draftLocationAreaSourceId,
      MapStyleConfig.draftLocationAreaFillLayerId,
      const FillLayerProperties(fillColor: '#14b8a6', fillOpacity: 0.18),
      belowLayerId: MapStyleConfig.selectionLayerId,
      enableInteraction: false,
    );
    await controller.addLineLayer(
      MapStyleConfig.draftLocationAreaSourceId,
      MapStyleConfig.draftLocationAreaStrokeLayerId,
      const LineLayerProperties(
        lineColor: '#0f766e',
        lineOpacity: 0.85,
        lineWidth: 2,
      ),
      belowLayerId: MapStyleConfig.selectionLayerId,
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(
      MapStyleConfig.draftLocationPointSourceId,
      _featureCollection(const []),
    );
    await controller.addCircleLayer(
      MapStyleConfig.draftLocationPointSourceId,
      MapStyleConfig.draftLocationPointLayerId,
      const CircleLayerProperties(
        circleRadius: 9,
        circleColor: '#14b8a6',
        circleOpacity: 0.72,
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
      ),
      belowLayerId: MapStyleConfig.selectionLayerId,
      enableInteraction: false,
    );
    _layersReady = true;
  }

  Future<void> setPoint({
    required MapLibreMapController controller,
    required GeoCoordinate? point,
  }) async {
    if (!_layersReady) return;
    await controller.setGeoJsonSource(
      MapStyleConfig.draftLocationPointSourceId,
      _featureCollection([
        if (point != null)
          {
            'type': 'Feature',
            'properties': <String, Object?>{},
            'geometry': {
              'type': 'Point',
              'coordinates': [point.lon, point.lat],
            },
          },
      ]),
    );
  }

  Future<void> setArea({
    required MapLibreMapController controller,
    required GeoCoordinate? center,
    required double radiusMeters,
  }) async {
    if (!_layersReady) return;
    await controller.setGeoJsonSource(
      MapStyleConfig.draftLocationAreaSourceId,
      _featureCollection([
        if (center != null)
          {
            'type': 'Feature',
            'properties': <String, Object?>{},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [_circleCoordinates(center, radiusMeters)],
            },
          },
      ]),
    );
    await setPoint(controller: controller, point: center);
  }

  Future<void> clear(MapLibreMapController controller) async {
    if (!_layersReady) return;
    await setPoint(controller: controller, point: null);
    await setArea(controller: controller, center: null, radiusMeters: 500);
  }

  static Map<String, Object?> _featureCollection(
    List<Map<String, Object?>> features,
  ) {
    return {'type': 'FeatureCollection', 'features': features};
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
