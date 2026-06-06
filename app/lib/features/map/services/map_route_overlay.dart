import 'package:maplibre_gl/maplibre_gl.dart';

import '../../routing/model/navigation_candidate.dart';
import 'map_style_config.dart';

class MapRouteOverlay {
  bool _routeLayersReady = false;

  Future<void> addRouteLayers(MapLibreMapController controller) async {
    _routeLayersReady = false;
    await controller.addGeoJsonSource(
      MapStyleConfig.routeAlternativesSourceId,
      _featureCollection(const []),
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
      _featureCollection(const []),
    );
    await controller.addLineLayer(
      MapStyleConfig.routeSelectedSourceId,
      MapStyleConfig.routeSelectedLayerId,
      const LineLayerProperties(
        lineColor: '#2563eb',
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
      _featureCollection(alternatives),
    );
    await controller.setGeoJsonSource(
      MapStyleConfig.routeSelectedSourceId,
      _featureCollection([?selectedCandidate]),
    );
  }

  Future<void> clear(MapLibreMapController controller) {
    return setRoutes(
      controller: controller,
      candidates: const [],
      selectedCandidate: null,
    );
  }

  static Map<String, Object?> _featureCollection(
    List<NavigationCandidate> candidates,
  ) {
    return {
      'type': 'FeatureCollection',
      'features': candidates
          .where((candidate) => candidate.geometry.length >= 2)
          .map(
            (candidate) => {
              'type': 'Feature',
              'properties': {'id': candidate.id},
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
}
