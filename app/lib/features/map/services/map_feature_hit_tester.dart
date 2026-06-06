import 'dart:math' as math;

import 'package:maplibre_gl/maplibre_gl.dart';

import '../model/rendered_map_feature.dart';
import 'map_style_config.dart';

class MapFeatureHitTester {
  const MapFeatureHitTester();

  Future<RenderedMapFeature?> nearestFeature({
    required math.Point<double> tapPoint,
    required List<RenderedMapFeature> features,
    required MapLibreMapController controller,
  }) async {
    if (features.isEmpty) return null;

    final featureDistances = <_FeatureDistance>[];
    for (final feature in features) {
      final screenPoint = await _screenPointForFeature(feature, controller);
      featureDistances.add(
        _FeatureDistance(
          feature,
          screenPoint == null
              ? double.infinity
              : _distance(tapPoint, screenPoint),
        ),
      );
    }

    featureDistances.sort((a, b) {
      final distanceCompare = a.distance.compareTo(b.distance);
      if (distanceCompare != 0) return distanceCompare;
      return _interactiveLayerPriority(
        a.feature.layerId,
      ).compareTo(_interactiveLayerPriority(b.feature.layerId));
    });

    return featureDistances.first.feature;
  }

  Future<math.Point<double>?> _screenPointForFeature(
    RenderedMapFeature feature,
    MapLibreMapController controller,
  ) async {
    final coordinates = feature.coordinates;
    if (coordinates == null) return null;

    final point = await controller.toScreenLocation(coordinates);
    return math.Point(point.x.toDouble(), point.y.toDouble());
  }

  static int _interactiveLayerPriority(String layerId) {
    final index = MapStyleConfig.interactiveLayerIds.indexOf(layerId);
    return index == -1 ? MapStyleConfig.interactiveLayerIds.length : index;
  }

  static double _distance(math.Point<double> a, math.Point<double> b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

class _FeatureDistance {
  const _FeatureDistance(this.feature, this.distance);

  final RenderedMapFeature feature;
  final double distance;
}
