import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../_shared/models/geo_coordinate.dart';
import '../../../_shared/models/transport_mode.dart';
import '../../../_shared/services/local_persistence_service.dart';
import '../model/itinerary_step_draft.dart';
import '../model/location_constraint.dart';
import '../model/time_constraint.dart';
import '../model/trip_draft.dart';

class TripDraftManager extends ChangeNotifier {
  TripDraftManager(this._persistenceService);

  static const _namespace = 'tripDrafts';
  static const _activeDraftId = 'active';

  final LocalPersistenceService _persistenceService;

  TripDraft? _draft;
  bool _isLoaded = false;

  TripDraft? get draft => _draft;
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
    final step = ItineraryStepDraft.create(
      id: 'step-${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      details: details.trim(),
      time: TimeConstraint(durationMinutes: durationMinutes),
      location: location,
    );
    _draft = draft.copyWith(
      steps: [...draft.steps, step],
      updatedAt: DateTime.now().toUtc(),
    );
    _changed();
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
}
