import 'package:flutter/foundation.dart';

import '../../../_shared/services/api_client.dart';
import '../model/trip_planning_session.dart';

class TripPlanningApiService {
  const TripPlanningApiService(this._apiClient);

  final ApiClient _apiClient;

  Future<String> startSession(TripPlanningRequest request) async {
    final response = await _apiClient.postJson(
      '/trip-planning/sessions',
      data: request.toJson(),
    );
    final sessionId = response['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) {
      throw const FormatException('Trip planning session response has no id.');
    }
    return sessionId;
  }

  Stream<TripPlanningEvent> watchEvents(String sessionId) {
    return _apiClient.sse('/trip-planning/sessions/$sessionId/events').map((
      sse,
    ) {
      final event = TripPlanningEvent.fromSse(sse);
      debugPrint(
        'TripPlanningApiService received SSE '
        'sessionId=$sessionId '
        'sseType=${sse.type} '
        'eventType=${event.type.apiValue} '
        'questionId=${event.question?.id} '
        'options=${event.question?.options.length ?? 0} '
        'message=${event.message}',
      );
      return event;
    });
  }

  Future<void> answerQuestion({
    required String sessionId,
    required TripPlanningAnswer answer,
  }) {
    return _apiClient.postNoContent(
      '/trip-planning/sessions/$sessionId/answers',
      data: answer.toJson(),
    );
  }

  Future<void> cancelSession(String sessionId) {
    return _apiClient.postNoContent(
      '/trip-planning/sessions/$sessionId/cancel',
    );
  }

  Future<Map<String, Object?>> getSession(String sessionId) {
    return _apiClient.getJson('/trip-planning/sessions/$sessionId');
  }
}
