import 'location_constraint.dart';
import 'time_constraint.dart';

enum ItineraryStepType {
  shop('shop', 'Shop', 'shopping_bag', 0xFF3B82F6),
  eat('eat', 'Eat', 'restaurant', 0xFFEF4444),
  party('party', 'Party', 'nightlife', 0xFFA855F7),
  walk('walk', 'Walk', 'directions_walk', 0xFF22C55E),
  sightsee('sightsee', 'Sightsee', 'photo_camera', 0xFFF59E0B),
  meander('meander', 'Meander', 'auto_awesome', 0xFF14B8A6),
  exactLocation('exactLocation', 'Exact location', 'place', 0xFF64748B);

  const ItineraryStepType(
    this.apiValue,
    this.defaultTitle,
    this.iconKey,
    this.colorValue,
  );

  final String apiValue;
  final String defaultTitle;
  final String iconKey;
  final int colorValue;

  String get detailHint => switch (this) {
    ItineraryStepType.shop => 'clothes, books, design shops',
    ItineraryStepType.eat => 'Chinese, casual lunch, wine bar',
    ItineraryStepType.party => 'clubs, live music, late drinks',
    ItineraryStepType.walk => 'riverside, parks, relaxed wander',
    ItineraryStepType.sightsee => 'views, landmarks, museums',
    ItineraryStepType.meander => 'mixed afternoon, surprise me',
    ItineraryStepType.exactLocation => 'what to do there',
  };

  static ItineraryStepType fromApiValue(String value) {
    return ItineraryStepType.values.firstWhere(
      (type) => type.apiValue == value,
      orElse: () =>
          throw FormatException('Unknown itinerary step type $value.'),
    );
  }
}

class ItineraryStepDraft {
  const ItineraryStepDraft({
    required this.id,
    required this.type,
    required this.title,
    required this.details,
    required this.time,
    required this.location,
  });

  factory ItineraryStepDraft.create({
    required String id,
    required ItineraryStepType type,
    required String details,
    required TimeConstraint time,
    required LocationConstraint location,
  }) {
    return ItineraryStepDraft(
      id: id,
      type: type,
      title: type.defaultTitle,
      details: details,
      time: time,
      location: location,
    );
  }

  factory ItineraryStepDraft.fromJson(Map<String, Object?> json) {
    return ItineraryStepDraft(
      id: json['id'] as String,
      type: ItineraryStepType.fromApiValue(json['type'] as String),
      title: json['title'] as String,
      details: json['details'] as String? ?? '',
      time: TimeConstraint.fromJson(_map(json['time'])),
      location: LocationConstraint.fromJson(_map(json['location'])),
    );
  }

  final String id;
  final ItineraryStepType type;
  final String title;
  final String details;
  final TimeConstraint time;
  final LocationConstraint location;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.apiValue,
    'title': title,
    'details': details,
    'time': time.toJson(),
    'location': location.toJson(),
    'iconKey': type.iconKey,
    'colorValue': type.colorValue,
  };

  ItineraryStepDraft copyWith({
    String? title,
    String? details,
    TimeConstraint? time,
    LocationConstraint? location,
  }) {
    return ItineraryStepDraft(
      id: id,
      type: type,
      title: title ?? this.title,
      details: details ?? this.details,
      time: time ?? this.time,
      location: location ?? this.location,
    );
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return Map<String, Object?>.from(value);
    throw const FormatException('Expected object.');
  }
}
