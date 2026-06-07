import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../_shared/services/local_persistence_service.dart';
import '../model/trip_plan.dart';

class TripPlanManager extends ChangeNotifier {
  TripPlanManager(this._persistenceService);

  static const _plansNamespace = 'tripPlans';
  static const _progressNamespace = 'tripProgress';
  static const _activePlanId = 'active';

  final LocalPersistenceService _persistenceService;

  TripPlan? _currentPlan;
  final Set<String> _completedItemIds = {};
  bool _isTripActive = false;

  TripPlan? get currentPlan => _currentPlan;
  Set<String> get completedItemIds => Set.unmodifiable(_completedItemIds);
  bool get isTripActive => _isTripActive;

  Future<void> loadActivePlan() async {
    final payload = await _persistenceService.getJson(
      namespace: _plansNamespace,
      id: _activePlanId,
    );
    if (payload != null) {
      _currentPlan = TripPlan.fromJson(payload);
    }

    final progress = await _persistenceService.getJson(
      namespace: _progressNamespace,
      id: _activePlanId,
    );
    final completed = progress?['completedItemIds'];
    _completedItemIds
      ..clear()
      ..addAll(
        completed is List ? completed.whereType<String>() : const <String>[],
      );
    _isTripActive = progress?['isTripActive'] == true;
    notifyListeners();
  }

  Future<void> setPlan(TripPlan plan) async {
    _currentPlan = plan;
    _completedItemIds.clear();
    _isTripActive = false;
    notifyListeners();
    await _persistenceService.putJson(
      namespace: _plansNamespace,
      id: _activePlanId,
      payload: plan.toJson(),
    );
    await _saveProgress();
  }

  void startTrip() {
    if (_currentPlan == null) return;
    _isTripActive = true;
    notifyListeners();
    unawaited(_saveProgress());
  }

  void stopTrip() {
    _isTripActive = false;
    notifyListeners();
    unawaited(_saveProgress());
  }

  void toggleItemDone(String itemId) {
    if (_completedItemIds.contains(itemId)) {
      _completedItemIds.remove(itemId);
    } else {
      _completedItemIds.add(itemId);
    }
    notifyListeners();
    unawaited(_saveProgress());
  }

  Future<void> _saveProgress() {
    return _persistenceService.putJson(
      namespace: _progressNamespace,
      id: _activePlanId,
      payload: {
        'isTripActive': _isTripActive,
        'completedItemIds': _completedItemIds.toList(),
      },
    );
  }
}
