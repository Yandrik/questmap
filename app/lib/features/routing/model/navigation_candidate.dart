import '../../../_shared/models/geo_coordinate.dart';
import '../../../_shared/models/transport_mode.dart';

class NavigationCandidate {
  const NavigationCandidate({
    required this.id,
    required this.mode,
    required this.durationSeconds,
    required this.summaryLabel,
    this.distanceMeters,
    this.geometry = const [],
    this.legs = const [],
  });

  final String id;
  final TransportMode mode;
  final int durationSeconds;
  final double? distanceMeters;
  final String summaryLabel;
  final List<GeoCoordinate> geometry;
  final List<NavigationLeg> legs;

  String get durationLabel {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes == 0
        ? '${hours}h'
        : '${hours}h ${remainingMinutes}min';
  }
}

class NavigationLeg {
  const NavigationLeg({
    required this.mode,
    required this.fromLabel,
    required this.toLabel,
    required this.durationSeconds,
    this.distanceMeters,
    this.geometry = const [],
    this.displayName,
  });

  final TransportMode mode;
  final String fromLabel;
  final String toLabel;
  final int durationSeconds;
  final double? distanceMeters;
  final List<GeoCoordinate> geometry;
  final String? displayName;
}

class NavigationCandidateParser {
  const NavigationCandidateParser._();

  static List<NavigationCandidate> fromValhalla({
    required Map<String, Object?> json,
    required TransportMode mode,
  }) {
    final candidates = <NavigationCandidate>[];
    final primaryTrip = _mapValue(json['trip']);
    if (primaryTrip != null) {
      candidates.add(_valhallaTrip(primaryTrip, mode, 'route-0'));
    }

    final alternates = json['alternates'];
    if (alternates is List) {
      for (var i = 0; i < alternates.length; i++) {
        final alternate = _mapValue(alternates[i]);
        final trip = _mapValue(alternate?['trip']) ?? alternate;
        if (trip == null) continue;
        candidates.add(_valhallaTrip(trip, mode, 'route-${i + 1}'));
      }
    }

    return candidates;
  }

  static List<NavigationCandidate> fromMotis(Map<String, Object?> json) {
    final itineraries = json['itineraries'];
    if (itineraries is! List) return const [];

    final candidates = <NavigationCandidate>[];
    for (var i = 0; i < itineraries.length; i++) {
      final itinerary = _mapValue(itineraries[i]);
      if (itinerary == null) continue;

      final legs = _motisLegs(itinerary['legs']);
      final duration =
          _intValue(itinerary['duration']) ??
          legs.fold<int>(0, (sum, leg) => sum + leg.durationSeconds);
      final distance = legs.fold<double>(
        0,
        (sum, leg) => sum + (leg.distanceMeters ?? 0),
      );
      candidates.add(
        NavigationCandidate(
          id: _stringValue(itinerary['id']) ?? 'transit-$i',
          mode: TransportMode.publicTransport,
          durationSeconds: duration,
          distanceMeters: distance == 0 ? null : distance,
          summaryLabel: _motisSummaryLabel(legs, duration),
          geometry: legs.expand((leg) => leg.geometry).toList(),
          legs: legs,
        ),
      );
    }
    return candidates;
  }

  static NavigationCandidate _valhallaTrip(
    Map<String, Object?> trip,
    TransportMode mode,
    String id,
  ) {
    final summary = _mapValue(trip['summary']);
    final duration = _intValue(summary?['time']) ?? 0;
    final lengthKm = _doubleValue(summary?['length']);
    final geometry = <GeoCoordinate>[
      ..._coordinatesFromAny(trip['shape']),
      ..._coordinatesFromValhallaLegs(trip['legs']),
    ];
    final distanceMeters = lengthKm == null ? null : lengthKm * 1000;
    return NavigationCandidate(
      id: id,
      mode: mode,
      durationSeconds: duration,
      distanceMeters: distanceMeters,
      summaryLabel: _distanceDurationLabel(distanceMeters, duration),
      geometry: geometry,
      legs: [
        NavigationLeg(
          mode: mode,
          fromLabel: 'Start',
          toLabel: 'Destination',
          durationSeconds: duration,
          distanceMeters: distanceMeters,
          geometry: geometry,
        ),
      ],
    );
  }

  static List<NavigationLeg> _motisLegs(Object? rawLegs) {
    if (rawLegs is! List) return const [];
    final legs = <NavigationLeg>[];
    for (final rawLeg in rawLegs) {
      final leg = _mapValue(rawLeg);
      if (leg == null) continue;
      final geometry = _coordinatesFromMotisGeometry(leg['legGeometry']);
      legs.add(
        NavigationLeg(
          mode: _transportModeFromMotis(_stringValue(leg['mode'])),
          fromLabel: _placeLabel(leg['from'], 'Start'),
          toLabel: _placeLabel(leg['to'], 'Destination'),
          durationSeconds: _intValue(leg['duration']) ?? 0,
          distanceMeters: _doubleValue(leg['distance']),
          geometry: geometry,
          displayName:
              _stringValue(leg['displayName']) ??
              _stringValue(leg['routeShortName']) ??
              _stringValue(leg['routeLongName']),
        ),
      );
    }
    return legs;
  }

  static List<GeoCoordinate> _coordinatesFromValhallaLegs(Object? rawLegs) {
    if (rawLegs is! List) return const [];
    return [
      for (final rawLeg in rawLegs)
        ..._coordinatesFromAny(_mapValue(rawLeg)?['shape']),
    ];
  }

  static List<GeoCoordinate> _coordinatesFromMotisGeometry(Object? value) {
    final geometry = _mapValue(value);
    if (geometry == null) return const [];
    final points = _stringValue(geometry['points']);
    final precision = _intValue(geometry['precision']) ?? 6;
    if (points == null || points.isEmpty) return const [];
    return decodePolyline(points, precision: precision);
  }

  static List<GeoCoordinate> _coordinatesFromAny(Object? value) {
    if (value == null) return const [];
    if (value is String) return decodePolyline(value, precision: 6);

    final map = _mapValue(value);
    if (map != null) {
      final geometry = _mapValue(map['geometry']) ?? map;
      if (_stringValue(geometry['type']) == 'LineString') {
        return _coordinatesFromGeoJsonList(geometry['coordinates']);
      }
    }

    return const [];
  }

  static List<GeoCoordinate> _coordinatesFromGeoJsonList(Object? value) {
    if (value is! List) return const [];
    return [
      for (final raw in value)
        if (raw is List && raw.length >= 2)
          GeoCoordinate(
            lon: _doubleValue(raw[0]) ?? 0,
            lat: _doubleValue(raw[1]) ?? 0,
          ),
    ];
  }

  static List<GeoCoordinate> decodePolyline(
    String encoded, {
    required int precision,
  }) {
    final factor = _pow10(precision);
    final coordinates = <GeoCoordinate>[];
    var index = 0;
    var lat = 0;
    var lon = 0;

    while (index < encoded.length) {
      final latResult = _decodePolylineValue(encoded, index);
      index = latResult.nextIndex;
      lat += latResult.value;

      final lonResult = _decodePolylineValue(encoded, index);
      index = lonResult.nextIndex;
      lon += lonResult.value;

      coordinates.add(GeoCoordinate(lat: lat / factor, lon: lon / factor));
    }
    return coordinates;
  }

  static _PolylineValue _decodePolylineValue(String encoded, int startIndex) {
    var index = startIndex;
    var result = 0;
    var shift = 0;
    int byte;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    final value = (result & 1) == 1 ? ~(result >> 1) : result >> 1;
    return _PolylineValue(value, index);
  }

  static TransportMode _transportModeFromMotis(String? mode) {
    return switch (mode) {
      'WALK' => TransportMode.walk,
      'BIKE' || 'RENTAL' => TransportMode.bike,
      'CAR' || 'CAR_PARKING' || 'CAR_DROPOFF' => TransportMode.drive,
      _ => TransportMode.publicTransport,
    };
  }

  static String _placeLabel(Object? place, String fallback) {
    final map = _mapValue(place);
    return _stringValue(map?['name']) ?? fallback;
  }

  static String _motisSummaryLabel(List<NavigationLeg> legs, int duration) {
    final transitLegs = legs
        .where((leg) => leg.mode == TransportMode.publicTransport)
        .map((leg) => leg.displayName)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();
    final prefix = transitLegs.isEmpty
        ? 'Public transport'
        : transitLegs.join(' + ');
    return '$prefix · ${_durationLabel(duration)}';
  }

  static String _distanceDurationLabel(double? distanceMeters, int duration) {
    final distance = distanceMeters == null
        ? null
        : distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
        : '${distanceMeters.round()} m';
    final time = _durationLabel(duration);
    return distance == null ? time : '$distance · $time';
  }

  static String _durationLabel(int durationSeconds) {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60}h ${minutes % 60}min';
  }

  static Map<String, Object?>? _mapValue(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return Map<String, Object?>.from(value);
    return null;
  }

  static String? _stringValue(Object? value) {
    if (value == null) return null;
    final string = value.toString();
    return string.isEmpty ? null : string;
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _doubleValue(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static double _pow10(int precision) {
    var value = 1.0;
    for (var i = 0; i < precision; i++) {
      value *= 10;
    }
    return value;
  }
}

class _PolylineValue {
  const _PolylineValue(this.value, this.nextIndex);

  final int value;
  final int nextIndex;
}
