import '../../../_shared/models/geo_coordinate.dart';
import '../../../_shared/models/transport_mode.dart';
import 'itinerary_step_draft.dart';
import 'trip_planner_mode.dart';

class TripDraft {
  const TripDraft({
    required this.id,
    required this.startLocation,
    this.plannerMode = TripPlannerMode.agent,
    required this.transportModes,
    required this.steps,
    this.endLocation,
    this.updatedAt,
  });

  factory TripDraft.empty({
    required String id,
    required GeoCoordinate startLocation,
  }) {
    return TripDraft(
      id: id,
      startLocation: startLocation,
      plannerMode: TripPlannerMode.agent,
      transportModes: const {TransportMode.walk, TransportMode.publicTransport},
      steps: const [],
      updatedAt: DateTime.now().toUtc(),
    );
  }

  factory TripDraft.fromJson(Map<String, Object?> json) {
    final rawModes = json['transportModes'];
    final rawSteps = json['steps'];
    return TripDraft(
      id: json['id'] as String,
      startLocation: GeoCoordinate.fromJson(_map(json['startLocation'])),
      plannerMode: json['plannerMode'] is String
          ? TripPlannerMode.fromApiValue(json['plannerMode'] as String)
          : TripPlannerMode.agent,
      endLocation: json['endLocation'] == null
          ? null
          : GeoCoordinate.fromJson(_map(json['endLocation'])),
      transportModes: rawModes is List
          ? rawModes
                .map((value) => TransportMode.fromApiValue(value as String))
                .toSet()
          : const {TransportMode.walk, TransportMode.publicTransport},
      steps: rawSteps is List
          ? rawSteps
                .map((step) => ItineraryStepDraft.fromJson(_map(step)))
                .toList()
          : const [],
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
    );
  }

  final String id;
  final GeoCoordinate startLocation;
  final TripPlannerMode plannerMode;
  final GeoCoordinate? endLocation;
  final Set<TransportMode> transportModes;
  final List<ItineraryStepDraft> steps;
  final DateTime? updatedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'startLocation': startLocation.toJson(),
    'plannerMode': plannerMode.apiValue,
    if (endLocation != null) 'endLocation': endLocation!.toJson(),
    'transportModes': transportModes.map((mode) => mode.apiValue).toList(),
    'steps': steps.map((step) => step.toJson()).toList(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  TripDraft copyWith({
    GeoCoordinate? startLocation,
    TripPlannerMode? plannerMode,
    GeoCoordinate? endLocation,
    Set<TransportMode>? transportModes,
    List<ItineraryStepDraft>? steps,
    DateTime? updatedAt,
    bool clearEndLocation = false,
  }) {
    return TripDraft(
      id: id,
      startLocation: startLocation ?? this.startLocation,
      plannerMode: plannerMode ?? this.plannerMode,
      endLocation: clearEndLocation ? null : endLocation ?? this.endLocation,
      transportModes: transportModes ?? this.transportModes,
      steps: steps ?? this.steps,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  throw const FormatException('Expected object.');
}
