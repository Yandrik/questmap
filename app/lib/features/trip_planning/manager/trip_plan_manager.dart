import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../_shared/services/local_persistence_service.dart';
import '../../../_shared/models/geo_coordinate.dart';
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
  String? _currentItemId;
  DateTime? _activeActivityStartedAt;

  TripPlan? get currentPlan => _currentPlan;
  Set<String> get completedItemIds => Set.unmodifiable(_completedItemIds);
  bool get isTripActive => _isTripActive;
  String? get currentItemId => _currentItemId;
  DateTime? get activeActivityStartedAt => _activeActivityStartedAt;

  int get currentItemIndex {
    final plan = _currentPlan;
    final id = _currentItemId;
    if (plan == null || id == null) return -1;
    return plan.items.indexWhere((item) => item.id == id);
  }

  TripPlanItem? get currentItem {
    final index = currentItemIndex;
    final plan = _currentPlan;
    if (plan == null || index < 0) return null;
    return plan.items[index];
  }

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
    _currentItemId = progress?['currentItemId'] as String?;
    _activeActivityStartedAt = _dateTime(progress?['activeActivityStartedAt']);
    if (_isTripActive && currentItem == null) {
      _advanceToNextIncomplete();
    }
    if (_isTripActive &&
        currentItem?.type == TripPlanItemType.activity &&
        _activeActivityStartedAt == null) {
      _activeActivityStartedAt = DateTime.now().toUtc();
    }
    notifyListeners();
  }

  Future<void> setPlan(TripPlan plan) async {
    _currentPlan = plan;
    _completedItemIds.clear();
    _isTripActive = false;
    _currentItemId = null;
    _activeActivityStartedAt = null;
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
    _completedItemIds.clear();
    _isTripActive = true;
    _currentItemId = _currentPlan!.items.isEmpty
        ? null
        : _currentPlan!.items.first.id;
    _activeActivityStartedAt = currentItem?.type == TripPlanItemType.activity
        ? DateTime.now().toUtc()
        : null;
    if (_currentItemId == null) {
      _isTripActive = false;
    }
    notifyListeners();
    unawaited(_saveProgress());
  }

  void stopTrip() {
    _isTripActive = false;
    _activeActivityStartedAt = null;
    notifyListeners();
    unawaited(_saveProgress());
  }

  Future<void> rejectPlan() async {
    _currentPlan = null;
    _completedItemIds.clear();
    _isTripActive = false;
    _currentItemId = null;
    _activeActivityStartedAt = null;
    notifyListeners();
    await Future.wait([
      _persistenceService.deleteJson(
        namespace: _plansNamespace,
        id: _activePlanId,
      ),
      _persistenceService.deleteJson(
        namespace: _progressNamespace,
        id: _activePlanId,
      ),
    ]);
  }

  bool markArrived() {
    final item = currentItem;
    if (!_isTripActive || item?.type != TripPlanItemType.travel) {
      return false;
    }
    _completedItemIds.add(item!.id);
    _advanceToNextIncomplete();
    notifyListeners();
    unawaited(_saveProgress());
    return true;
  }

  bool completeCurrentActivity() {
    final item = currentItem;
    if (!_isTripActive || item?.type != TripPlanItemType.activity) {
      return false;
    }
    _completedItemIds.add(item!.id);
    _advanceToNextIncomplete();
    notifyListeners();
    unawaited(_saveProgress());
    return true;
  }

  bool maybeMarkArrived(
    GeoCoordinate? userLocation, {
    double thresholdMeters = 60,
  }) {
    final destination = destinationForCurrentTravel;
    if (!_isTripActive || userLocation == null || destination == null) {
      return false;
    }
    if (_distanceMeters(userLocation, destination) > thresholdMeters) {
      return false;
    }
    return markArrived();
  }

  GeoCoordinate? get destinationForCurrentTravel {
    final item = currentItem;
    if (item?.type != TripPlanItemType.travel) return null;
    final nextActivity = _nextItemAfterCurrent(type: TripPlanItemType.activity);
    if (nextActivity?.location != null) return nextActivity!.location;
    if (item!.geometry.isNotEmpty) return item.geometry.last;
    for (final segment in item.segments.reversed) {
      if (segment.geometry.isNotEmpty) return segment.geometry.last;
    }
    return null;
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
        if (_currentItemId != null) 'currentItemId': _currentItemId,
        if (_activeActivityStartedAt != null)
          'activeActivityStartedAt': _activeActivityStartedAt!
              .toIso8601String(),
      },
    );
  }

  void _advanceToNextIncomplete() {
    final plan = _currentPlan;
    if (plan == null) {
      _currentItemId = null;
      _isTripActive = false;
      _activeActivityStartedAt = null;
      return;
    }

    final currentIndex = currentItemIndex;
    final startIndex = currentIndex < 0 ? 0 : currentIndex + 1;
    for (var index = startIndex; index < plan.items.length; index++) {
      final item = plan.items[index];
      if (_completedItemIds.contains(item.id)) continue;
      _currentItemId = item.id;
      _activeActivityStartedAt = item.type == TripPlanItemType.activity
          ? DateTime.now().toUtc()
          : null;
      return;
    }

    _currentItemId = null;
    _isTripActive = false;
    _activeActivityStartedAt = null;
  }

  TripPlanItem? _nextItemAfterCurrent({TripPlanItemType? type}) {
    final plan = _currentPlan;
    final index = currentItemIndex;
    if (plan == null || index < 0) return null;
    for (final item in plan.items.skip(index + 1)) {
      if (type == null || item.type == type) return item;
    }
    return null;
  }

  static DateTime? _dateTime(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static double _distanceMeters(GeoCoordinate first, GeoCoordinate second) {
    const earthRadiusMeters = 6371000.0;
    final firstLat = _radians(first.lat);
    final secondLat = _radians(second.lat);
    final deltaLat = _radians(second.lat - first.lat);
    final deltaLon = _radians(second.lon - first.lon);
    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(firstLat) *
            math.cos(secondLat) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
