import '../../../_shared/models/geo_coordinate.dart';
import '../../../_shared/models/transit_leg_details.dart';
import '../../../_shared/models/transport_mode.dart';
import 'itinerary_step_draft.dart';
import 'location_constraint.dart';

enum TripPlanItemType {
  activity('activity'),
  travel('travel');

  const TripPlanItemType(this.apiValue);

  final String apiValue;

  static TripPlanItemType fromApiValue(String value) {
    return TripPlanItemType.values.firstWhere(
      (type) => type.apiValue == value,
      orElse: () => throw FormatException('Unknown plan item type $value.'),
    );
  }
}

class TripPlan {
  const TripPlan({
    required this.id,
    required this.title,
    required this.items,
    this.summary,
  });

  factory TripPlan.fromJson(Map<String, Object?> json) {
    final rawItems = json['items'];
    return TripPlan(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Trip plan',
      summary: json['summary'] as String?,
      items: rawItems is List
          ? rawItems.map((item) => TripPlanItem.fromJson(_map(item))).toList()
          : const [],
    );
  }

  final String id;
  final String title;
  final String? summary;
  final List<TripPlanItem> items;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    if (summary != null) 'summary': summary,
    'items': items.map((item) => item.toJson()).toList(),
  };
}

class TripPlanItem {
  const TripPlanItem({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.reasoning,
    this.sourceDraftStepId,
    this.stepType,
    this.transportMode,
    this.startTime,
    this.endTime,
    this.location,
    this.visualTarget,
    this.geometry = const [],
    this.segments = const [],
  });

  factory TripPlanItem.fromJson(Map<String, Object?> json) {
    final rawGeometry = json['geometry'];
    final rawSegments = json['segments'];
    return TripPlanItem(
      id: json['id'] as String,
      type: TripPlanItemType.fromApiValue(json['type'] as String),
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      reasoning: json['reasoning'] as String?,
      sourceDraftStepId: json['sourceDraftStepId'] as String?,
      stepType: json['stepType'] == null
          ? null
          : ItineraryStepType.fromApiValue(json['stepType'] as String),
      transportMode: json['transportMode'] == null
          ? null
          : TransportMode.fromApiValue(json['transportMode'] as String),
      startTime: _dateTime(json['startTime']),
      endTime: _dateTime(json['endTime']),
      location: json['location'] == null
          ? null
          : GeoCoordinate.fromJson(_map(json['location'])),
      visualTarget: json['visualTarget'] == null
          ? null
          : LocationConstraint.fromJson(_map(json['visualTarget'])),
      geometry: rawGeometry is List
          ? rawGeometry
                .map((coordinate) => GeoCoordinate.fromJson(_map(coordinate)))
                .toList()
          : const [],
      segments: rawSegments is List
          ? rawSegments
                .map((segment) => TripRouteSegment.fromJson(_map(segment)))
                .toList()
          : const [],
    );
  }

  final String id;
  final TripPlanItemType type;
  final String title;
  final String description;
  final String? reasoning;
  final String? sourceDraftStepId;
  final ItineraryStepType? stepType;
  final TransportMode? transportMode;
  final DateTime? startTime;
  final DateTime? endTime;
  final GeoCoordinate? location;
  final LocationConstraint? visualTarget;
  final List<GeoCoordinate> geometry;
  final List<TripRouteSegment> segments;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.apiValue,
    'title': title,
    'description': description,
    if (reasoning != null) 'reasoning': reasoning,
    if (sourceDraftStepId != null) 'sourceDraftStepId': sourceDraftStepId,
    if (stepType != null) 'stepType': stepType!.apiValue,
    if (transportMode != null) 'transportMode': transportMode!.apiValue,
    if (startTime != null) 'startTime': startTime!.toIso8601String(),
    if (endTime != null) 'endTime': endTime!.toIso8601String(),
    if (location != null) 'location': location!.toJson(),
    if (visualTarget != null) 'visualTarget': visualTarget!.toJson(),
    'geometry': geometry.map((coordinate) => coordinate.toJson()).toList(),
    if (segments.isNotEmpty)
      'segments': segments.map((segment) => segment.toJson()).toList(),
  };
}

class TripRouteSegment {
  const TripRouteSegment({
    required this.transportMode,
    this.geometry = const [],
    this.description,
    this.transitDetails,
  });

  factory TripRouteSegment.fromJson(Map<String, Object?> json) {
    final rawGeometry = json['geometry'];
    return TripRouteSegment(
      transportMode: TransportMode.fromApiValue(
        json['transportMode'] as String,
      ),
      description: json['description'] as String?,
      transitDetails: json['transitDetails'] == null
          ? null
          : TransitLegDetails.fromJson(_map(json['transitDetails'])),
      geometry: rawGeometry is List
          ? rawGeometry
                .map((coordinate) => GeoCoordinate.fromJson(_map(coordinate)))
                .toList()
          : const [],
    );
  }

  final TransportMode transportMode;
  final List<GeoCoordinate> geometry;
  final String? description;
  final TransitLegDetails? transitDetails;

  Map<String, Object?> toJson() => {
    'transportMode': transportMode.apiValue,
    if (description != null) 'description': description,
    if (transitDetails != null) 'transitDetails': transitDetails!.toJson(),
    'geometry': geometry.map((coordinate) => coordinate.toJson()).toList(),
  };
}

DateTime? _dateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.parse(value);
  throw const FormatException('Expected date-time string.');
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  throw const FormatException('Expected object.');
}
