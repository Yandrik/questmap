import '../../../_shared/models/geo_coordinate.dart';
import 'itinerary_step_draft.dart';

enum TripLocationPickKind {
  exactPoint,
  aroundPoint,
  areaCircle;

  bool get usesArea => this == TripLocationPickKind.areaCircle;
}

class PendingTripLocationPick {
  const PendingTripLocationPick({
    required this.type,
    required this.details,
    required this.durationMinutes,
    required this.insertIndex,
    required this.kind,
    this.areaCenter,
    this.radiusMeters = 500,
  });

  final ItineraryStepType type;
  final String details;
  final int durationMinutes;
  final int insertIndex;
  final TripLocationPickKind kind;
  final GeoCoordinate? areaCenter;
  final double radiusMeters;

  PendingTripLocationPick copyWith({
    ItineraryStepType? type,
    String? details,
    int? durationMinutes,
    int? insertIndex,
    TripLocationPickKind? kind,
    GeoCoordinate? areaCenter,
    bool clearAreaCenter = false,
    double? radiusMeters,
  }) {
    return PendingTripLocationPick(
      type: type ?? this.type,
      details: details ?? this.details,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      insertIndex: insertIndex ?? this.insertIndex,
      kind: kind ?? this.kind,
      areaCenter: clearAreaCenter ? null : areaCenter ?? this.areaCenter,
      radiusMeters: radiusMeters ?? this.radiusMeters,
    );
  }
}
