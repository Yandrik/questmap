import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../_shared/models/geo_coordinate.dart';
import '../../../_shared/models/transport_mode.dart';
import '../../routing/model/navigation_candidate.dart';
import 'map_style_config.dart';

class MapRouteOverlay {
  bool _routeLayersReady = false;

  Future<void> addRouteLayers(MapLibreMapController controller) async {
    _routeLayersReady = false;
    await controller.addGeoJsonSource(
      MapStyleConfig.routeAlternativesSourceId,
      MapRouteOverlayGeoJson.alternatives(const []),
    );
    await controller.addLineLayer(
      MapStyleConfig.routeAlternativesSourceId,
      MapStyleConfig.routeAlternativesLayerId,
      const LineLayerProperties(
        lineColor: '#64748b',
        lineOpacity: 0.42,
        lineWidth: 4,
      ),
      belowLayerId: MapStyleConfig.selectionLayerId,
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(
      MapStyleConfig.routeSelectedSourceId,
      MapRouteOverlayGeoJson.selected(null),
    );
    await controller.addLineLayer(
      MapStyleConfig.routeSelectedSourceId,
      MapStyleConfig.routeSelectedLayerId,
      const LineLayerProperties(
        lineColor: ['get', 'color'],
        lineOpacity: 0.88,
        lineWidth: 6,
      ),
      belowLayerId: MapStyleConfig.selectionLayerId,
      enableInteraction: false,
    );
    _routeLayersReady = true;
  }

  Future<void> setRoutes({
    required MapLibreMapController controller,
    required List<NavigationCandidate> candidates,
    required NavigationCandidate? selectedCandidate,
  }) async {
    if (!_routeLayersReady) return;

    final selectedId = selectedCandidate?.id;
    final alternatives = candidates
        .where((candidate) => candidate.id != selectedId)
        .toList();
    await controller.setGeoJsonSource(
      MapStyleConfig.routeAlternativesSourceId,
      MapRouteOverlayGeoJson.alternatives(alternatives),
    );
    await controller.setGeoJsonSource(
      MapStyleConfig.routeSelectedSourceId,
      MapRouteOverlayGeoJson.selected(selectedCandidate),
    );
  }

  Future<void> clear(MapLibreMapController controller) {
    return setRoutes(
      controller: controller,
      candidates: const [],
      selectedCandidate: null,
    );
  }
}

class MapRouteOverlayGeoJson {
  const MapRouteOverlayGeoJson._();

  static Map<String, Object?> alternatives(
    List<NavigationCandidate> candidates,
  ) {
    return {
      'type': 'FeatureCollection',
      'features': candidates
          .where((candidate) => candidate.geometry.length >= 2)
          .map(
            (candidate) => {
              'type': 'Feature',
              'properties': {'id': candidate.id, 'color': '#64748b'},
              'geometry': {
                'type': 'LineString',
                'coordinates': candidate.geometry
                    .map((coordinate) => [coordinate.lon, coordinate.lat])
                    .toList(),
              },
            },
          )
          .toList(),
    };
  }

  static Map<String, Object?> selected(NavigationCandidate? candidate) {
    if (candidate == null) return _featureCollection(const []);
    final legFeatures = candidate.mode == TransportMode.publicTransport
        ? _legFeatures(candidate)
        : const <Map<String, Object?>>[];
    if (legFeatures.isNotEmpty) return _featureCollection(legFeatures);
    return _featureCollection([
      _lineFeature(candidate.geometry, candidate.id, '#2563eb'),
    ]);
  }

  static List<Map<String, Object?>> _legFeatures(
    NavigationCandidate candidate,
  ) {
    return [
      for (var index = 0; index < candidate.legs.length; index++)
        if (candidate.legs[index].geometry.length >= 2)
          _lineFeature(
            candidate.legs[index].geometry,
            '${candidate.id}-leg-$index',
            _modeColor(candidate.legs[index].mode),
            transportMode: candidate.legs[index].mode,
          ),
    ];
  }

  static Map<String, Object?> _lineFeature(
    List<GeoCoordinate> coordinates,
    String id,
    String color, {
    TransportMode? transportMode,
  }) {
    return {
      'type': 'Feature',
      'properties': {
        'id': id,
        'color': color,
        if (transportMode != null) 'transportMode': transportMode.apiValue,
      },
      'geometry': {
        'type': 'LineString',
        'coordinates': coordinates
            .map((coordinate) => [coordinate.lon, coordinate.lat])
            .toList(),
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

  static String _modeColor(TransportMode mode) {
    return switch (mode) {
      TransportMode.walk => '#22c55e',
      TransportMode.bike => '#14b8a6',
      TransportMode.drive => '#f97316',
      TransportMode.publicTransport => '#a855f7',
    };
  }
}
