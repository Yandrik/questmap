import 'package:maplibre_gl/maplibre_gl.dart';

class RenderedMapFeature {
  const RenderedMapFeature({
    required this.layerId,
    required this.sourceLayer,
    required this.properties,
    required this.coordinates,
  });

  factory RenderedMapFeature.fromFeature(Map<Object?, Object?> feature) {
    final layer = feature['layer'];
    final properties = feature['properties'];

    final normalizedProperties = _propertyMap(properties);
    final inferredSourceLayer = _inferSourceLayer(normalizedProperties);

    return RenderedMapFeature(
      layerId: _stringValue(_mapValue(layer)?['id']) ?? 'rendered point',
      sourceLayer:
          _stringValue(
            _mapValue(layer)?['source-layer'] ??
                _mapValue(layer)?['sourceLayer'],
          ) ??
          inferredSourceLayer,
      properties: normalizedProperties,
      coordinates: _pointCoordinates(feature['geometry']),
    );
  }

  final String layerId;
  final String sourceLayer;
  final Map<String, String> properties;
  final LatLng? coordinates;

  String get layerSummary => '$sourceLayer / $layerId';

  String get typeSummary {
    final displayType = _displayType;
    final values = <String>[
      ?displayType,
      if (sourceLayer.isNotEmpty) sourceLayer,
      if (layerId.isNotEmpty) layerId,
    ];
    return values.join(' / ');
  }

  String get title {
    for (final key in const ['name', 'name_en', 'housenumber']) {
      final value = properties[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return _displayType ?? sourceLayer;
  }

  String? get _displayType {
    final value = properties['subclass'] ?? properties['class'];
    if (value == null || value.isEmpty) return null;
    return value
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static Map<Object?, Object?>? _mapValue(Object? value) {
    if (value is Map<Object?, Object?>) return value;
    if (value is Map) return Map<Object?, Object?>.from(value);
    return null;
  }

  static String? _stringValue(Object? value) {
    if (value == null) return null;
    final string = value.toString();
    return string.isEmpty ? null : string;
  }

  static Map<String, String> _propertyMap(Object? value) {
    final raw = _mapValue(value);
    if (raw == null) return {};

    final entries = <MapEntry<String, String>>[];
    for (final entry in raw.entries) {
      final key = _stringValue(entry.key);
      final entryValue = _stringValue(entry.value);
      if (key == null || entryValue == null) continue;
      if (key.startsWith('name:') && key != 'name:en') continue;
      entries.add(MapEntry(key, entryValue));
    }

    entries.sort((a, b) => a.key.compareTo(b.key));
    return Map<String, String>.fromEntries(entries.take(24));
  }

  static LatLng? _pointCoordinates(Object? value) {
    final geometry = _mapValue(value);
    if (geometry == null) return null;
    if (_stringValue(geometry['type']) != 'Point') return null;

    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.length < 2) return null;

    final longitude = _doubleValue(coordinates[0]);
    final latitude = _doubleValue(coordinates[1]);
    if (latitude == null || longitude == null) return null;

    return LatLng(latitude, longitude);
  }

  static double? _doubleValue(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String _inferSourceLayer(Map<String, String> properties) {
    if (properties.containsKey('housenumber')) return 'housenumber';
    if (properties.containsKey('iata') || properties.containsKey('icao')) {
      return 'aerodrome_label';
    }
    if (properties.containsKey('ele') || properties.containsKey('ele_ft')) {
      return 'mountain_peak';
    }
    if (properties.containsKey('class') && properties.containsKey('subclass')) {
      return 'poi';
    }
    if (properties.containsKey('class') && properties.containsKey('rank')) {
      return 'poi';
    }
    if (properties.containsKey('ref')) return 'transportation_name';
    if (properties.containsKey('name')) return 'place';
    return 'OpenMapTiles';
  }
}
