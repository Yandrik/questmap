import '../../../_shared/models/geo_coordinate.dart';
import 'itinerary_step_draft.dart';

enum TripLocationPickKind {
  exactPoint,
  aroundPoint,
  areaCircle;

  bool get usesArea => this == TripLocationPickKind.areaCircle;
}

enum TripLocationPickTargetType {
  insertStep,
  startLocation,
  endLocation,
  stepLocation,
}

class TripLocationPickTarget {
  const TripLocationPickTarget._({required this.type, this.stepId});

  const TripLocationPickTarget.insertStep()
    : this._(type: TripLocationPickTargetType.insertStep);

  const TripLocationPickTarget.startLocation()
    : this._(type: TripLocationPickTargetType.startLocation);

  const TripLocationPickTarget.endLocation()
    : this._(type: TripLocationPickTargetType.endLocation);

  const TripLocationPickTarget.stepLocation(String stepId)
    : this._(type: TripLocationPickTargetType.stepLocation, stepId: stepId);

  final TripLocationPickTargetType type;
  final String? stepId;
}

class PendingTripLocationPick {
  const PendingTripLocationPick({
    required this.type,
    required this.details,
    required this.durationMinutes,
    required this.insertIndex,
    required this.kind,
    this.target = const TripLocationPickTarget.insertStep(),
    this.areaCenter,
    this.radiusMeters = 500,
  });

  final ItineraryStepType type;
  final String details;
  final int durationMinutes;
  final int insertIndex;
  final TripLocationPickKind kind;
  final TripLocationPickTarget target;
  final GeoCoordinate? areaCenter;
  final double radiusMeters;

  PendingTripLocationPick copyWith({
    ItineraryStepType? type,
    String? details,
    int? durationMinutes,
    int? insertIndex,
    TripLocationPickKind? kind,
    TripLocationPickTarget? target,
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
      target: target ?? this.target,
      areaCenter: clearAreaCenter ? null : areaCenter ?? this.areaCenter,
      radiusMeters: radiusMeters ?? this.radiusMeters,
    );
  }
}
