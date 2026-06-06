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
      updatedAt: DateTime.now().toUtc(),
    );
    _pendingLocationPick = null;
    _changed();
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
