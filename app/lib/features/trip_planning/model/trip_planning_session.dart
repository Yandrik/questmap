import '../../../_shared/models/geo_coordinate.dart';
import '../../../_shared/models/transport_mode.dart';
import '../../../_shared/services/api_client.dart';
import 'itinerary_step_draft.dart';
import 'trip_plan.dart';
import 'trip_planner_mode.dart';

class TripPlanningRequest {
  const TripPlanningRequest({
    required this.draftId,
    this.plannerMode = TripPlannerMode.agent,
    required this.startLocation,
    required this.transportModes,
    required this.steps,
    this.endLocation,
  });

  final String draftId;
  final TripPlannerMode plannerMode;
  final GeoCoordinate startLocation;
  final GeoCoordinate? endLocation;
  final List<TransportMode> transportModes;
  final List<ItineraryStepDraft> steps;

  Map<String, Object?> toJson() => {
    'draftId': draftId,
    'plannerMode': plannerMode.apiValue,
    'startLocation': startLocation.toJson(),
    if (endLocation != null) 'endLocation': endLocation!.toJson(),
    'transportModes': transportModes.map((mode) => mode.apiValue).toList(),
    'steps': _stepsJson(),
  };

  List<Map<String, Object?>> _stepsJson() {
    if (steps.isEmpty) return const [];

    return [
      steps.first
          .copyWith(
            time: steps.first.time.startTime == null
                ? steps.first.time.copyWith(startTime: DateTime.now().toUtc())
                : steps.first.time,
          )
          .toJson(),
      ...steps.skip(1).map((step) => step.toJson()),
    ];
  }
}

enum TripPlanningQuestionKind {
  yesNo('yesNo'),
  number('number'),
  text('text'),
  selection('selection'),
  routeChoice('routeChoice');

  const TripPlanningQuestionKind(this.apiValue);

  final String apiValue;

  static TripPlanningQuestionKind fromApiValue(String value) {
    return TripPlanningQuestionKind.values.firstWhere(
      (kind) => kind.apiValue == value,
      orElse: () => throw FormatException('Unknown question kind $value.'),
    );
  }
}

class TripPlanningQuestion {
  const TripPlanningQuestion({
    required this.id,
    required this.kind,
    required this.prompt,
    this.options = const [],
    this.unit,
  });

  factory TripPlanningQuestion.fromJson(Map<String, Object?> json) {
    final options = json['options'];
    return TripPlanningQuestion(
      id: json['id'] as String,
      kind: TripPlanningQuestionKind.fromApiValue(json['kind'] as String),
      prompt: json['prompt'] as String,
      unit: json['unit'] as String?,
      options: options is List
          ? options
                .map((option) => TripQuestionOption.fromJson(_map(option)))
                .toList()
          : const [],
    );
  }

  final String id;
  final TripPlanningQuestionKind kind;
  final String prompt;
  final List<TripQuestionOption> options;
  final String? unit;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.apiValue,
    'prompt': prompt,
    if (unit != null) 'unit': unit,
    'options': options.map((option) => option.toJson()).toList(),
  };
}

class TripQuestionOption {
  const TripQuestionOption({
    required this.id,
    required this.title,
    this.description,
    this.imageUrl,
    this.payload,
  });

  factory TripQuestionOption.fromJson(Map<String, Object?> json) {
    return TripQuestionOption(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      payload: _optionalMap(json['payload']),
    );
  }

  final String id;
  final String title;
  final String? description;
  final String? imageUrl;
  final Map<String, Object?>? payload;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    if (description != null) 'description': description,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (payload != null) 'payload': payload,
  };
}

class TripPlanningAnswer {
  const TripPlanningAnswer({required this.questionId, required this.value});

  final String questionId;
  final Object? value;

  Map<String, Object?> toJson() => {'questionId': questionId, 'value': value};
}

enum TripPlanningEventType {
  status('status'),
  question('question'),
  partialPlan('partialPlan'),
  finalPlan('finalPlan'),
  error('error'),
  done('done');

  const TripPlanningEventType(this.apiValue);

  final String apiValue;

  static TripPlanningEventType fromApiValue(String value) {
    return TripPlanningEventType.values.firstWhere(
      (type) => type.apiValue == value,
      orElse: () => throw FormatException('Unknown planning event $value.'),
    );
  }
}

class TripPlanningEvent {
  const TripPlanningEvent({
    required this.type,
    this.message,
    this.question,
    this.plan,
  });

  factory TripPlanningEvent.fromSse(ServerSentEvent event) {
    final type = TripPlanningEventType.fromApiValue(
      event.data['type'] as String? ?? event.type,
    );
    return TripPlanningEvent(
      type: type,
      message: event.data['message'] as String?,
      question: event.data['question'] == null
          ? null
          : TripPlanningQuestion.fromJson(_map(event.data['question'])),
      plan: event.data['plan'] == null
          ? null
          : TripPlan.fromJson(_map(event.data['plan'])),
    );
  }

  final TripPlanningEventType type;
  final String? message;
  final TripPlanningQuestion? question;
  final TripPlan? plan;
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  throw const FormatException('Expected object.');
}

Map<String, Object?>? _optionalMap(Object? value) {
  if (value == null) return null;
  return _map(value);
}
