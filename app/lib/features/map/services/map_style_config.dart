import 'package:maplibre_gl/maplibre_gl.dart';

class MapStyleConfig {
  const MapStyleConfig._();

  static const initialCameraPosition = CameraPosition(
    target: LatLng(37.7749, -122.4194),
    zoom: 16,
  );

  static const selectionSourceId = 'meander-selection';
  static const selectionLayerId = 'meander-selection-circle';
  static const routeAlternativesSourceId = 'meander-route-alternatives';
  static const routeAlternativesLayerId = 'meander-route-alternatives-line';
  static const routeSelectedSourceId = 'meander-route-selected';
  static const routeSelectedLayerId = 'meander-route-selected-line';
  static const draftLocationPointSourceId = 'meander-draft-location-point';
  static const draftLocationPointLayerId =
      'meander-draft-location-point-circle';
  static const draftLocationAreaSourceId = 'meander-draft-location-area';
  static const draftLocationAreaFillLayerId =
      'meander-draft-location-area-fill';
  static const draftLocationAreaStrokeLayerId =
      'meander-draft-location-area-stroke';

  static const interactiveLayerIds = <String>[
    'poi-icons-priority',
    'poi-dots-known-dense',
    'poi-dots-other',
    'mountain-peak-points',
    'aerodrome-points',
    'water-name-points',
    'transportation-name-points',
    'poi-labels',
    'housenumber-labels',
    'place-labels',
    'transportation-labels',
  ];
}
