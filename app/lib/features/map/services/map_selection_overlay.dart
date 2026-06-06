import 'package:maplibre_gl/maplibre_gl.dart';

import 'map_style_config.dart';

class MapSelectionOverlay {
  Symbol? _waypointSymbol;
  bool _selectionLayerReady = false;

  Future<void> addSelectionLayer(MapLibreMapController controller) async {
    _selectionLayerReady = false;
    await controller.addGeoJsonSource(
      MapStyleConfig.selectionSourceId,
      _selectionFeatureCollection(),
    );
    await controller.addCircleLayer(
      MapStyleConfig.selectionSourceId,
      MapStyleConfig.selectionLayerId,
      const CircleLayerProperties(
        circleRadius: 12,
        circleColor: '#0066ff',
        circleOpacity: 0.28,
        circleStrokeColor: '#0066ff',
        circleStrokeWidth: 2,
        circleStrokeOpacity: 0.85,
      ),
      belowLayerId: 'poi-dots-other',
      enableInteraction: false,
    );
    _selectionLayerReady = true;
  }

  Future<void> setSelectionCircle(
    LatLng? coordinates,
    MapLibreMapController controller,
  ) async {
    if (!_selectionLayerReady) return;

    await controller.setGeoJsonSource(
      MapStyleConfig.selectionSourceId,
      _selectionFeatureCollection(coordinates),
    );
  }

  Future<void> setWaypointMarker(
    LatLng? coordinates,
    MapLibreMapController controller,
  ) async {
    final existingSymbol = _waypointSymbol;
    if (coordinates == null) {
      if (existingSymbol != null) {
        await controller.removeSymbol(existingSymbol);
        _waypointSymbol = null;
      }
      return;
    }

    final options = SymbolOptions(
      geometry: coordinates,
      iconImage: 'omt-marker',
      iconSize: 1.8,
      iconColor: '#0066ff',
      iconHaloColor: '#ffffff',
      iconHaloWidth: 1.5,
    );

    if (existingSymbol == null) {
      _waypointSymbol = await controller.addSymbol(options);
    } else {
      await controller.updateSymbol(existingSymbol, options);
    }
  }

  static Map<String, dynamic> _selectionFeatureCollection([
    LatLng? coordinates,
  ]) {
    return {
      'type': 'FeatureCollection',
      'features': [
        if (coordinates != null)
          {
            'type': 'Feature',
            'properties': <String, Object?>{},
            'geometry': {
              'type': 'Point',
              'coordinates': [coordinates.longitude, coordinates.latitude],
            },
          },
      ],
    };
  }
}
