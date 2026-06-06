import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../_shared/services/local_persistence_service.dart';
import '../model/trip_draft.dart';
import '../model/trip_plan.dart';
import '../model/trip_planning_session.dart';
import '../services/trip_planning_api_service.dart';
import 'trip_plan_manager.dart';

class TripAgentManager extends ChangeNotifier {
  TripAgentManager(
    this._apiService,
    this._planManager,
    this._persistenceService,
  );

  static const _sessionNamespace = 'tripAgentSessions';
  static const _activeSessionId = 'active';

  final TripPlanningApiService _apiService;
  final TripPlanManager _planManager;
  final LocalPersistenceService _persistenceService;

  StreamSubscription<TripPlanningEvent>? _eventsSubscription;
  String? _sessionId;
  bool _isPlanning = false;
  String? _statusMessage;
  String? _errorMessage;
  TripPlanningQuestion? _question;
  TripPlan? _partialPlan;

  String? get sessionId => _sessionId;
  bool get isPlanning => _isPlanning;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  TripPlanningQuestion? get question => _question;
  TripPlan? get partialPlan => _partialPlan;

  Future<void> startPlanning(TripDraft draft) async {
    await _eventsSubscription?.cancel();
    _isPlanning = true;
    _statusMessage = 'Considering trip plans...';
    _errorMessage = null;
    _question = null;
    _partialPlan = null;
    notifyListeners();

    try {
      final request = TripPlanningRequest(
        draftId: draft.id,
        startLocation: draft.startLocation,
        endLocation: draft.endLocation,
        transportModes: draft.transportModes.toList(),
        steps: draft.steps,
      );
      _sessionId = await _apiService.startSession(request);
      await _persistSession('running');
      _eventsSubscription = _apiService
          .watchEvents(_sessionId!)
          .listen(_handleEvent, onError: _handleError, cancelOnError: false);
      notifyListeners();
    } on Exception catch (error) {
      _isPlanning = false;
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> answerQuestion(Object? value) async {
    final sessionId = _sessionId;
    final question = _question;
    if (sessionId == null || question == null) return;
    await _apiService.answerQuestion(
      sessionId: sessionId,
      answer: TripPlanningAnswer(questionId: question.id, value: value),
    );
    _question = null;
    _statusMessage = 'Applying your answer...';
    notifyListeners();
  }

  Future<void> cancelPlanning() async {
    final sessionId = _sessionId;
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    if (sessionId != null) {
      await _apiService.cancelSession(sessionId);
    }
    _isPlanning = false;
    _question = null;
    _statusMessage = 'Planning cancelled.';
    await _persistSession('cancelled');
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _handleEvent(TripPlanningEvent event) async {
    switch (event.type) {
      case TripPlanningEventType.status:
        _statusMessage = event.message ?? _statusMessage;
      case TripPlanningEventType.question:
        _question = event.question;
        _statusMessage = event.message ?? _statusMessage;
      case TripPlanningEventType.partialPlan:
        _partialPlan = event.plan ?? _partialPlan;
        _statusMessage = event.message ?? 'Building your trip...';
      case TripPlanningEventType.finalPlan:
        final plan = event.plan;
        if (plan != null) {
          await _planManager.setPlan(plan);
        }
        _partialPlan = plan ?? _partialPlan;
        _isPlanning = false;
        _question = null;
        _statusMessage = event.message ?? 'Trip plan ready.';
        await _persistSession('finished');
      case TripPlanningEventType.error:
        _isPlanning = false;
        _question = null;
        _errorMessage = event.message ?? 'Trip planning failed.';
        await _persistSession('error');
      case TripPlanningEventType.done:
        _isPlanning = false;
        _question = null;
        await _persistSession('finished');
    }
    notifyListeners();
  }

  void _handleError(Object error, StackTrace stackTrace) {
    _isPlanning = false;
    _question = null;
    _errorMessage = error.toString();
    notifyListeners();
    unawaited(_persistSession('error'));
  }

  Future<void> _persistSession(String status) {
    final sessionId = _sessionId;
    if (sessionId == null) return Future.value();
    return _persistenceService.putJson(
      namespace: _sessionNamespace,
      id: _activeSessionId,
      payload: {
        'sessionId': sessionId,
        'status': status,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  @override
  void dispose() {
    unawaited(_eventsSubscription?.cancel());
    super.dispose();
  }
}
