import 'package:maplibre_gl/maplibre_gl.dart';

import 'rendered_map_feature.dart';

class SelectedMapTarget {
  const SelectedMapTarget._({
    required this.coordinates,
    required this.isWaypoint,
    this.feature,
  });

  factory SelectedMapTarget.feature({
    required RenderedMapFeature feature,
    required LatLng fallbackCoordinates,
  }) => SelectedMapTarget._(
    coordinates: feature.coordinates ?? fallbackCoordinates,
    feature: feature,
    isWaypoint: false,
  );

  factory SelectedMapTarget.waypoint({required LatLng coordinates}) =>
      SelectedMapTarget._(coordinates: coordinates, isWaypoint: true);

  final LatLng coordinates;
  final RenderedMapFeature? feature;
  final bool isWaypoint;

  String get name => feature?.title ?? 'Waypoint';

  String get subtitle {
    final feature = this.feature;
    if (feature == null) return coordinateLabel;
    return feature.typeSummary;
  }

  String get coordinateLabel =>
      'Lat ${coordinates.latitude.toStringAsFixed(6)}, '
      'Lon ${coordinates.longitude.toStringAsFixed(6)}';
}
