import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../_shared/models/geo_coordinate.dart';
import '../../../_shared/models/transport_mode.dart';
import '../../../_shared/services/local_persistence_service.dart';
import '../model/itinerary_step_draft.dart';
import '../model/location_constraint.dart';
import '../model/pending_trip_location_pick.dart';
import '../model/time_constraint.dart';
import '../model/trip_draft.dart';
import '../model/trip_planner_mode.dart';

class TripDraftManager extends ChangeNotifier {
  TripDraftManager(this._persistenceService);

  static const _namespace = 'tripDrafts';
  static const _activeDraftId = 'active';

  final LocalPersistenceService _persistenceService;

  TripDraft? _draft;
  PendingTripLocationPick? _pendingLocationPick;
  bool _isLoaded = false;

  TripDraft? get draft => _draft;
  PendingTripLocationPick? get pendingLocationPick => _pendingLocationPick;
  bool get isLoaded => _isLoaded;
  bool get hasSteps => _draft?.steps.isNotEmpty ?? false;

  Future<void> ensureDraft({required GeoCoordinate startLocation}) async {
    if (_draft != null) return;
    final stored = await _persistenceService.getJson(
      namespace: _namespace,
      id: _activeDraftId,
    );
    _draft = stored == null
        ? TripDraft.empty(id: _activeDraftId, startLocation: startLocation)
        : TripDraft.fromJson(stored);
    _isLoaded = true;
    notifyListeners();
    unawaited(_save());
  }

  Future<void> loadOrCreate({required GeoCoordinate startLocation}) {
    return ensureDraft(startLocation: startLocation);
  }

  void setStartLocation(GeoCoordinate location) {
    final draft = _requireDraft();
    _draft = draft.copyWith(
      startLocation: location,
      updatedAt: DateTime.now().toUtc(),
    );
    _changed();
  }

  void setEndLocation(GeoCoordinate? location) {
    final draft = _requireDraft();
    _draft = draft.copyWith(
      endLocation: location,
      clearEndLocation: location == null,
      updatedAt: DateTime.now().toUtc(),
    );
    _changed();
  }

  void setPlannerMode(TripPlannerMode mode) {
    final draft = _requireDraft();
    if (draft.plannerMode == mode) return;
    _draft = draft.copyWith(
      plannerMode: mode,
      updatedAt: DateTime.now().toUtc(),
    );
    _changed();
  }

  void toggleTransportMode(TransportMode mode) {
    final draft = _requireDraft();
    final modes = {...draft.transportModes};
    if (modes.contains(mode)) {
      if (modes.length == 1) return;
      modes.remove(mode);
    } else {
      modes.add(mode);
    }
    _draft = draft.copyWith(
      transportModes: modes,
      updatedAt: DateTime.now().toUtc(),
    );
    _changed();
  }

  void addStep({
    required ItineraryStepType type,
    required String details,
    required LocationConstraint location,
    int durationMinutes = 60,
  }) {
    final draft = _requireDraft();
    insertStep(
      index: draft.steps.length,
      type: type,
      details: details,
      durationMinutes: durationMinutes,
      location: location,
    );
  }

  void insertStep({
    required int index,
    required ItineraryStepType type,
    required String details,
    required LocationConstraint location,
    int durationMinutes = 60,
  }) {
    final draft = _requireDraft();
    final insertIndex = _clampInsertIndex(index, draft.steps.length);
    final step = ItineraryStepDraft.create(
      id: 'step-${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      details: details.trim(),
      time: TimeConstraint(durationMinutes: durationMinutes),
      location: location,
    );
    _draft = draft.copyWith(
      steps: [
        ...draft.steps.take(insertIndex),
        step,
        ...draft.steps.skip(insertIndex),
      ],
      updatedAt: DateTime.now().toUtc(),
    );
    _changed();
  }

  void beginLocationPick({
    required int index,
    required ItineraryStepType type,
    required String details,
    required int durationMinutes,
    required TripLocationPickKind kind,
    GeoCoordinate? areaCenter,
    double radiusMeters = 500,
  }) {
    final draft = _requireDraft();
    _pendingLocationPick = PendingTripLocationPick(
      type: type,
      details: details.trim(),
      durationMinutes: durationMinutes,
      insertIndex: _clampInsertIndex(index, draft.steps.length),
      kind: kind,
      target: const TripLocationPickTarget.insertStep(),
      areaCenter: areaCenter,
      radiusMeters: radiusMeters,
    );
    notifyListeners();
  }

  void beginStartLocationPick() {
    _requireDraft();
    _pendingLocationPick = const PendingTripLocationPick(
      type: ItineraryStepType.exactLocation,
      details: '',
      durationMinutes: 0,
      insertIndex: 0,
      kind: TripLocationPickKind.exactPoint,
      target: TripLocationPickTarget.startLocation(),
    );
    notifyListeners();
  }

  void beginEndLocationPick() {
    final draft = _requireDraft();
    _pendingLocationPick = PendingTripLocationPick(
      type: ItineraryStepType.exactLocation,
      details: '',
      durationMinutes: 0,
      insertIndex: draft.steps.length,
      kind: TripLocationPickKind.exactPoint,
      target: const TripLocationPickTarget.endLocation(),
    );
    notifyListeners();
  }

  void beginStepLocationPick({
    required String stepId,
    required TripLocationPickKind kind,
    GeoCoordinate? areaCenter,
    double radiusMeters = 500,
  }) {
    final draft = _requireDraft();
    final step = draft.steps.firstWhere(
      (step) => step.id == stepId,
      orElse: () => throw StateError('Step $stepId does not exist.'),
    );
    _pendingLocationPick = PendingTripLocationPick(
      type: step.type,
      details: step.details,
      durationMinutes: step.time.durationMinutes,
      insertIndex: draft.steps.indexWhere((step) => step.id == stepId),
      kind: kind,
      target: TripLocationPickTarget.stepLocation(stepId),
      areaCenter: areaCenter,
      radiusMeters: radiusMeters,
    );
    notifyListeners();
  }

  void updatePendingAreaCenter(GeoCoordinate center) {
    final pending = _requirePendingLocationPick();
    if (!pending.kind.usesArea) {
      throw StateError('Only area location picks can update an area center.');
    }
    _pendingLocationPick = pending.copyWith(areaCenter: center);
    notifyListeners();
  }

  void updatePendingAreaRadius(double radiusMeters) {
    final pending = _requirePendingLocationPick();
    _pendingLocationPick = pending.copyWith(radiusMeters: radiusMeters);
    notifyListeners();
  }

  void completePointPick(GeoCoordinate point) {
    final pending = _requirePendingLocationPick();
    final location = switch (pending.kind) {
      TripLocationPickKind.exactPoint => LocationConstraint.exactPoint(point),
      TripLocationPickKind.aroundPoint => LocationConstraint.aroundPoint(point),
      TripLocationPickKind.areaCircle => throw StateError(
        'Area location picks require completeAreaPick.',
      ),
    };
    _completePendingPick(location);
  }

  void completeAreaPick({
    required GeoCoordinate center,
    required double radiusMeters,
  }) {
    final pending = _requirePendingLocationPick();
    if (!pending.kind.usesArea) {
      throw StateError('Point location picks require completePointPick.');
    }
    _completePendingPick(
      LocationConstraint.areaCircle(center: center, radiusMeters: radiusMeters),
    );
  }

  void cancelLocationPick() {
    if (_pendingLocationPick == null) return;
    _pendingLocationPick = null;
    notifyListeners();
  }

  void updateStep(ItineraryStepDraft step) {
    final draft = _requireDraft();
    _draft = draft.copyWith(
      steps: [
        for (final existing in draft.steps)
          if (existing.id == step.id) step else existing,
      ],
      updatedAt: DateTime.now().toUtc(),
    );
    _changed();
  }

  void removeStep(String stepId) {
    final draft = _requireDraft();
    _draft = draft.copyWith(
      steps: draft.steps.where((step) => step.id != stepId).toList(),
      updatedAt: DateTime.now().toUtc(),
    );
    _changed();
  }

  Future<void> resetDraft() async {
    _draft = null;
    _pendingLocationPick = null;
    _isLoaded = false;
    notifyListeners();
    await _persistenceService.deleteJson(
      namespace: _namespace,
      id: _activeDraftId,
    );
  }

  Future<void> saveNow() => _save();

  TripDraft _requireDraft() {
    final draft = _draft;
    if (draft == null) {
      throw StateError('Trip draft has not been initialized.');
    }
    return draft;
  }

  PendingTripLocationPick _requirePendingLocationPick() {
    final pending = _pendingLocationPick;
    if (pending == null) {
      throw StateError('No trip location pick is pending.');
    }
    return pending;
  }

  void _completePendingPick(LocationConstraint location) {
    final pending = _requirePendingLocationPick();
    final draft = _requireDraft();
    final now = DateTime.now().toUtc();

    switch (pending.target.type) {
      case TripLocationPickTargetType.startLocation:
        final point = _locationPoint(location);
        if (point == null) {
          throw StateError('Start location requires a point.');
        }
        _draft = draft.copyWith(startLocation: point, updatedAt: now);
        _pendingLocationPick = null;
        _changed();
        return;
      case TripLocationPickTargetType.endLocation:
        final point = _locationPoint(location);
        if (point == null) {
          throw StateError('End location requires a point.');
        }
        _draft = draft.copyWith(endLocation: point, updatedAt: now);
        _pendingLocationPick = null;
        _changed();
        return;
      case TripLocationPickTargetType.stepLocation:
        final stepId = pending.target.stepId;
        if (stepId == null) {
          throw StateError('Step location target requires a step id.');
        }
        _draft = draft.copyWith(
          steps: [
            for (final step in draft.steps)
              if (step.id == stepId)
                step.copyWith(location: location)
              else
                step,
          ],
          updatedAt: now,
        );
        _pendingLocationPick = null;
        _changed();
        return;
      case TripLocationPickTargetType.insertStep:
        break;
    }

    final insertIndex = _clampInsertIndex(
      pending.insertIndex,
      draft.steps.length,
    );
    final step = ItineraryStepDraft.create(
      id: 'step-${DateTime.now().microsecondsSinceEpoch}',
      type: pending.type,
      details: pending.details,
      time: TimeConstraint(durationMinutes: pending.durationMinutes),
      location: location,
    );
    _draft = draft.copyWith(
      steps: [
        ...draft.steps.take(insertIndex),
        step,
        ...draft.steps.skip(insertIndex),
      ],
      updatedAt: now,
    );
    _pendingLocationPick = null;
    _changed();
  }

  static GeoCoordinate? _locationPoint(LocationConstraint location) {
    return switch (location.type) {
      LocationConstraintType.exactPoint ||
      LocationConstraintType.aroundPoint => location.point,
      LocationConstraintType.areaCircle => location.center,
      LocationConstraintType.wherever => null,
    };
  }

  void _changed() {
    notifyListeners();
    unawaited(_save());
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    await _persistenceService.putJson(
      namespace: _namespace,
      id: _activeDraftId,
      payload: draft.toJson(),
    );
  }

  static int _clampInsertIndex(int index, int length) {
    if (index < 0) return 0;
    if (index > length) return length;
    return index;
  }
}
