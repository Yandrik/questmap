class GeoCoordinate {
  const GeoCoordinate({required this.lat, required this.lon, this.label});

  factory GeoCoordinate.fromJson(Map<String, Object?> json) {
    return GeoCoordinate(
      lat: _requiredDouble(json['lat'], 'lat'),
      lon: _requiredDouble(json['lon'], 'lon'),
      label: json['label'] as String?,
    );
  }

  final double lat;
  final double lon;
  final String? label;

  Map<String, Object?> toJson() => {
    'lat': lat,
    'lon': lon,
    if (label != null) 'label': label,
  };

  String get coordinateLabel =>
      'Lat ${lat.toStringAsFixed(6)}, Lon ${lon.toStringAsFixed(6)}';

  String get motisPlace => '$lat,$lon';

  GeoCoordinate copyWith({double? lat, double? lon, String? label}) {
    return GeoCoordinate(
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      label: label ?? this.label,
    );
  }

  static double _requiredDouble(Object? value, String field) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw FormatException('Expected numeric $field.');
  }
}
