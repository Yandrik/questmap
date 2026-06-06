import '../../../_shared/models/geo_coordinate.dart';

enum LocationConstraintType {
  exactPoint('exactPoint'),
  aroundPoint('aroundPoint'),
  areaCircle('areaCircle'),
  wherever('wherever');

  const LocationConstraintType(this.apiValue);

  final String apiValue;

  static LocationConstraintType fromApiValue(String value) {
    return LocationConstraintType.values.firstWhere(
      (type) => type.apiValue == value,
      orElse: () =>
          throw FormatException('Unknown location constraint $value.'),
    );
  }
}

class LocationConstraint {
  const LocationConstraint._({
    required this.type,
    this.point,
    this.center,
    this.radiusMeters,
    this.maxTransportMinutes,
  });

  factory LocationConstraint.exactPoint(GeoCoordinate point) {
    return LocationConstraint._(
      type: LocationConstraintType.exactPoint,
      point: point,
    );
  }

  factory LocationConstraint.aroundPoint(GeoCoordinate point) {
    return LocationConstraint._(
      type: LocationConstraintType.aroundPoint,
      point: point,
    );
  }

  factory LocationConstraint.areaCircle({
    required GeoCoordinate center,
    required double radiusMeters,
  }) {
    return LocationConstraint._(
      type: LocationConstraintType.areaCircle,
      center: center,
      radiusMeters: radiusMeters,
    );
  }

  factory LocationConstraint.wherever({int maxTransportMinutes = 15}) {
    return LocationConstraint._(
      type: LocationConstraintType.wherever,
      maxTransportMinutes: maxTransportMinutes,
    );
  }

  factory LocationConstraint.fromJson(Map<String, Object?> json) {
    final type = LocationConstraintType.fromApiValue(json['type'] as String);
    return switch (type) {
      LocationConstraintType.exactPoint => LocationConstraint.exactPoint(
        GeoCoordinate.fromJson(_requiredMap(json['point'], 'point')),
      ),
      LocationConstraintType.aroundPoint => LocationConstraint.aroundPoint(
        GeoCoordinate.fromJson(_requiredMap(json['point'], 'point')),
      ),
      LocationConstraintType.areaCircle => LocationConstraint.areaCircle(
        center: GeoCoordinate.fromJson(_requiredMap(json['center'], 'center')),
        radiusMeters: _requiredDouble(json['radiusMeters'], 'radiusMeters'),
      ),
      LocationConstraintType.wherever => LocationConstraint.wherever(
        maxTransportMinutes: _intValue(json['maxTransportMinutes']) ?? 15,
      ),
    };
  }

  final LocationConstraintType type;
  final GeoCoordinate? point;
  final GeoCoordinate? center;
  final double? radiusMeters;
  final int? maxTransportMinutes;

  Map<String, Object?> toJson() => {
    'type': type.apiValue,
    if (point != null) 'point': point!.toJson(),
    if (center != null) 'center': center!.toJson(),
    if (radiusMeters != null) 'radiusMeters': radiusMeters,
    if (maxTransportMinutes != null) 'maxTransportMinutes': maxTransportMinutes,
  };

  static Map<String, Object?> _requiredMap(Object? value, String field) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return Map<String, Object?>.from(value);
    throw FormatException('Expected object $field.');
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double _requiredDouble(Object? value, String field) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw FormatException('Expected number $field.');
  }
}
