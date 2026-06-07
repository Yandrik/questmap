import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

import '../../../_shared/models/geo_coordinate.dart';
import '../../../_shared/models/transport_mode.dart';
import '../../map/manager/map_interaction_manager.dart';
import '../../map/model/selected_map_target.dart';
import '../manager/trip_agent_manager.dart';
import '../manager/trip_draft_manager.dart';
import '../manager/trip_plan_manager.dart';
import '../model/itinerary_step_draft.dart';
import '../model/location_constraint.dart';
import '../model/pending_trip_location_pick.dart';
import '../model/trip_plan.dart';
import '../model/trip_draft.dart';

class TripComposerPanel extends WatchingWidget {
  const TripComposerPanel({
    required this.onClose,
    this.selectedTarget,
    this.compact = false,
    this.scrollController,
    super.key,
  });

  final VoidCallback onClose;
  final SelectedMapTarget? selectedTarget;
  final bool compact;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final manager = watchIt<TripDraftManager>();
    final planManager = watchIt<TripPlanManager>();
    final agentManager = watchIt<TripAgentManager>();
    final lastShownPlanningError = createOnce(
      () => ValueNotifier<String?>(null),
    );
    registerChangeNotifierHandler<TripAgentManager>(
      target: agentManager,
      handler: (context, manager, cancel) {
        final error = manager.errorMessage;
        if (error == null) {
          lastShownPlanningError.value = null;
          return;
        }
        if (lastShownPlanningError.value == error) return;
        lastShownPlanningError.value = error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Trip planning failed: $error'),
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: manager.clearError,
            ),
          ),
        );
      },
    );
    final draft = manager.draft;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 8 : 0, 0, compact ? 8 : 0, 8),
        child: Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surface,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, compact ? 8 : 12, 12, 12),
            child: draft == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(onClose: onClose, onReset: _resetDraft),
                      const SizedBox(height: 12),
                      _TransportModeSelector(draft: draft),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: EdgeInsets.zero,
                          children: [
                            _TripLocationInput(
                              label: 'Start',
                              value: _coordinateLabel(draft.startLocation),
                              icon: Icons.trip_origin,
                              fullWidth: true,
                              onTap: _beginStartLocationPick,
                            ),
                            const SizedBox(height: 10),
                            if (draft.steps.isEmpty)
                              _EmptyDraftState(
                                onAdd: () => _showActivityDialog(context),
                              )
                            else
                              for (
                                var index = 0;
                                index < draft.steps.length;
                                index++
                              ) ...[
                                if (index == 0)
                                  _InsertStepButton(
                                    highlighted: false,
                                    onPressed: () => _showActivityDialog(
                                      context,
                                      insertIndex: 0,
                                    ),
                                  ),
                                _ItineraryStepCard(
                                  step: draft.steps[index],
                                  onEdit: () => _showActivityDialog(
                                    context,
                                    editStep: draft.steps[index],
                                  ),
                                  onEditLocation: () => _beginStepLocationPick(
                                    draft.steps[index],
                                  ),
                                ),
                                _InsertStepButton(
                                  highlighted:
                                      index < draft.steps.length - 1 &&
                                      _hasLargeGapAfter(draft.steps, index),
                                  onPressed: () => _showActivityDialog(
                                    context,
                                    insertIndex: index + 1,
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                            _TripLocationInput(
                              label: 'End',
                              value: draft.endLocation == null
                                  ? 'Add end location'
                                  : _coordinateLabel(draft.endLocation!),
                              icon: Icons.flag_outlined,
                              fullWidth: true,
                              muted: draft.endLocation == null,
                              onTap: _beginEndLocationPick,
                              onClear: draft.endLocation == null
                                  ? null
                                  : () => di<TripDraftManager>().setEndLocation(
                                      null,
                                    ),
                            ),
                          ],
                        ),
                      ),
                      if (planManager.currentPlan != null) ...[
                        const SizedBox(height: 10),
                        _TripPlanSection(
                          planManager: planManager,
                          onStarted: onClose,
                        ),
                      ],
                      if (agentManager.errorMessage != null) ...[
                        const SizedBox(height: 10),
                        _PlanningErrorBanner(
                          message: agentManager.errorMessage!,
                          onDismiss: agentManager.clearError,
                        ),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _showActivityDialog(
                                context,
                                insertIndex: draft.steps.length,
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text('Add activity'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed:
                                  draft.steps.isEmpty || agentManager.isPlanning
                                  ? null
                                  : () => agentManager.startPlanning(draft),
                              icon: const Icon(Icons.auto_awesome),
                              label: const Text('Plan trip'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _showActivityDialog(
    BuildContext context, {
    int? insertIndex,
    ItineraryStepDraft? editStep,
  }) async {
    final manager = di<TripDraftManager>();
    final targetIndex = insertIndex ?? manager.draft?.steps.length ?? 0;
    final result = await showDialog<_ActivityDialogResult>(
      context: context,
      builder: (context) => _ActivityPickerDialog(
        selectedTarget: selectedTarget,
        initialStep: editStep,
      ),
    );
    if (result == null || !context.mounted) return;
    final location = result.location;
    if (location != null) {
      if (editStep == null) {
        manager.insertStep(
          index: targetIndex,
          type: result.type,
          details: result.details,
          durationMinutes: result.durationMinutes,
          location: location,
        );
      } else {
        manager.updateStep(
          editStep.copyWith(
            type: result.type,
            details: result.details,
            time: editStep.time.copyWith(
              durationMinutes: result.durationMinutes,
            ),
            location: location,
          ),
        );
      }
      return;
    }

    final pickKind = result.pickKind;
    if (pickKind == null) return;
    if (editStep == null) {
      manager.beginLocationPick(
        index: targetIndex,
        type: result.type,
        details: result.details,
        durationMinutes: result.durationMinutes,
        kind: pickKind,
        areaCenter: result.areaCenter,
        radiusMeters: result.radiusMeters,
      );
    } else {
      manager.updateStep(
        editStep.copyWith(
          type: result.type,
          details: result.details,
          time: editStep.time.copyWith(durationMinutes: result.durationMinutes),
        ),
      );
      manager.beginStepLocationPick(
        stepId: editStep.id,
        kind: pickKind,
        areaCenter: result.areaCenter,
        radiusMeters: result.radiusMeters,
      );
    }
    di<MapInteractionManager>().setMode(
      pickKind.usesArea
          ? MapInteractionMode.drawArea
          : MapInteractionMode.selectPoint,
    );
  }

  void _beginStartLocationPick() {
    di<TripDraftManager>().beginStartLocationPick();
    di<MapInteractionManager>().setMode(MapInteractionMode.selectStart);
  }

  void _beginEndLocationPick() {
    di<TripDraftManager>().beginEndLocationPick();
    di<MapInteractionManager>().setMode(MapInteractionMode.selectEnd);
  }

  static void _beginStepLocationPick(ItineraryStepDraft step) {
    final location = step.location;
    final kind = _pickKindForLocation(location);
    if (kind == null) return;
    di<TripDraftManager>().beginStepLocationPick(
      stepId: step.id,
      kind: kind,
      areaCenter: location.center,
      radiusMeters: location.radiusMeters ?? 500,
    );
    di<MapInteractionManager>().setMode(
      kind.usesArea
          ? MapInteractionMode.drawArea
          : MapInteractionMode.selectPoint,
    );
  }

  static bool _hasLargeGapAfter(List<ItineraryStepDraft> steps, int index) {
    if (index >= steps.length - 1) return false;
    final currentStart = steps[index].time.startTime;
    final nextStart = steps[index + 1].time.startTime;
    if (currentStart == null || nextStart == null) return false;
    final currentEnd = currentStart.add(
      Duration(minutes: steps[index].time.durationMinutes),
    );
    return nextStart.difference(currentEnd).inMinutes > 30;
  }

  Future<void> _resetDraft() async {
    await di<TripDraftManager>().resetDraft();
    di<MapInteractionManager>().setMode(MapInteractionMode.browse);
    onClose();
  }
}

class _PlanningErrorBanner extends StatelessWidget {
  const _PlanningErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: theme.colorScheme.onErrorContainer,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              tooltip: 'Dismiss planning error',
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18),
              color: theme.colorScheme.onErrorContainer,
            ),
          ],
        ),
      ),
    );
  }
}

class _InsertStepButton extends StatelessWidget {
  const _InsertStepButton({required this.onPressed, required this.highlighted});

  final VoidCallback onPressed;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Tooltip(
          message: 'Insert activity here',
          child: IconButton(
            style: IconButton.styleFrom(
              backgroundColor: highlighted
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              foregroundColor: highlighted
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.primary,
              fixedSize: const Size.square(34),
            ),
            onPressed: onPressed,
            icon: const Icon(Icons.add, size: 18),
          ),
        ),
      ),
    );
  }
}

class _TripPlanSection extends StatelessWidget {
  const _TripPlanSection({required this.planManager, required this.onStarted});

  final TripPlanManager planManager;
  final VoidCallback onStarted;

  @override
  Widget build(BuildContext context) {
    final plan = planManager.currentPlan;
    if (plan == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.checklist, color: theme.colorScheme.primary),
              ],
            ),
            if (plan.summary != null)
              Text(plan.summary!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in plan.items)
                    _TripPlanItemReviewTile(item: item),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => di<TripPlanManager>().rejectPlan(),
                    icon: const Icon(Icons.close),
                    label: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      di<TripPlanManager>().startTrip();
                      onStarted();
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TripPlanItemReviewTile extends StatelessWidget {
  const _TripPlanItemReviewTile({required this.item});

  final TripPlanItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = item.reasoning == null || item.reasoning!.isEmpty
        ? item.description
        : '${item.description}\nReasoning: ${item.reasoning}';

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        item.type == TripPlanItemType.travel ? Icons.route : Icons.place,
      ),
      title: Text(item.title, style: theme.textTheme.bodyMedium),
      subtitle: Text(subtitle, maxLines: 4, overflow: TextOverflow.ellipsis),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose, required this.onReset});

  final VoidCallback onClose;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(Icons.route, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Trip',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Reset trip draft',
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _TransportModeSelector extends StatelessWidget {
  const _TransportModeSelector({required this.draft});

  final TripDraft draft;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final mode in TransportMode.values)
          FilterChip(
            label: Text(mode.displayLabel),
            selected: draft.transportModes.contains(mode),
            onSelected: (_) => di<TripDraftManager>().toggleTransportMode(mode),
            avatar: Icon(_modeIcon(mode), size: 18),
          ),
      ],
    );
  }

  IconData _modeIcon(TransportMode mode) {
    return switch (mode) {
      TransportMode.walk => Icons.directions_walk,
      TransportMode.bike => Icons.directions_bike,
      TransportMode.drive => Icons.directions_car,
      TransportMode.publicTransport => Icons.directions_transit,
    };
  }
}

class _TripLocationInput extends StatelessWidget {
  const _TripLocationInput({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.fullWidth = false,
    this.muted = false,
    this.onClear,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final bool fullWidth;
  final bool muted;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final input = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          suffixIcon: onClear == null
              ? const Icon(Icons.search, size: 18)
              : IconButton(
                  tooltip: 'Clear $label',
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 18),
                ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
        ),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: muted ? theme.colorScheme.onSurfaceVariant : null,
            fontStyle: muted ? FontStyle.italic : null,
          ),
        ),
      ),
    );

    if (fullWidth) return input;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 112, maxWidth: 170),
      child: input,
    );
  }
}

class _EmptyDraftState extends StatelessWidget {
  const _EmptyDraftState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: TextButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: Text(
          'Add your first activity',
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _ItineraryStepCard extends StatelessWidget {
  const _ItineraryStepCard({
    required this.step,
    required this.onEdit,
    required this.onEditLocation,
  });

  final ItineraryStepDraft step;
  final VoidCallback onEdit;
  final VoidCallback onEditLocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(step.type.colorValue);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Tooltip(
                  message: 'Edit activity',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onEdit,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SizedBox.square(
                        dimension: 40,
                        child: Icon(_stepIcon(step.type), color: color),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (step.details.isNotEmpty)
                        Text(
                          step.details,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (step.location.type != LocationConstraintType.wherever) ...[
                  const SizedBox(width: 0),
                  Flexible(
                    child: _TripLocationInput(
                      label: 'Location',
                      value: _locationConstraintLabel(step.location),
                      icon: Icons.search,
                      onTap: onEditLocation,
                    ),
                  ),
                ],
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => di<TripDraftManager>().removeStep(step.id),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _StartTimeButton(step: step)),
                const SizedBox(width: 8),
                Expanded(child: _DurationMenu(step: step)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StartTimeButton extends StatelessWidget {
  const _StartTimeButton({required this.step});

  final ItineraryStepDraft step;

  @override
  Widget build(BuildContext context) {
    final startTime = step.time.startTime;
    final label = startTime == null
        ? 'Any start'
        : TimeOfDay.fromDateTime(startTime).format(context);

    return OutlinedButton.icon(
      onPressed: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: startTime == null
              ? TimeOfDay.now()
              : TimeOfDay.fromDateTime(startTime),
        );
        if (picked == null || !context.mounted) return;
        final now = DateTime.now();
        final nextStart = DateTime(
          now.year,
          now.month,
          now.day,
          picked.hour,
          picked.minute,
        );
        di<TripDraftManager>().updateStep(
          step.copyWith(time: step.time.copyWith(startTime: nextStart)),
        );
      },
      icon: const Icon(Icons.schedule),
      label: Text(label),
    );
  }
}

const _activityDurationOptions = [
  5,
  10,
  15,
  20,
  25,
  30,
  45,
  60,
  90,
  120,
  150,
  180,
  240,
];

class _DurationMenu extends StatelessWidget {
  const _DurationMenu({required this.step});

  final ItineraryStepDraft step;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: _activityDurationOptions.contains(step.time.durationMinutes)
          ? step.time.durationMinutes
          : 60,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.timer),
        prefixIconConstraints: BoxConstraints(minWidth: 32, minHeight: 32),
        contentPadding: EdgeInsetsDirectional.only(end: 8),
        border: OutlineInputBorder(),
      ),
      items: [
        for (final duration in _activityDurationOptions)
          DropdownMenuItem(
            value: duration,
            child: Text(_durationLabel(duration)),
          ),
      ],
      onChanged: (duration) {
        if (duration == null) return;
        di<TripDraftManager>().updateStep(
          step.copyWith(time: step.time.copyWith(durationMinutes: duration)),
        );
      },
    );
  }

  static String _durationLabel(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return remaining == 0 ? '${hours}h' : '${hours}h ${remaining}min';
  }
}

class _ActivityPickerDialog extends StatefulWidget {
  const _ActivityPickerDialog({required this.selectedTarget, this.initialStep});

  final SelectedMapTarget? selectedTarget;
  final ItineraryStepDraft? initialStep;

  @override
  State<_ActivityPickerDialog> createState() => _ActivityPickerDialogState();
}

class _ActivityPickerDialogState extends State<_ActivityPickerDialog> {
  ItineraryStepType _type = ItineraryStepType.meander;
  String _details = '';
  int _durationMinutes = 60;
  _LocationChoice _locationChoice = _LocationChoice.wherever;
  late final TextEditingController _detailsController;

  @override
  void initState() {
    super.initState();
    final step = widget.initialStep;
    if (step != null) {
      _type = step.type;
      _details = step.details;
      _durationMinutes = step.time.durationMinutes;
      _locationChoice = _locationChoiceForLocation(step.location);
    }
    _detailsController = TextEditingController(text: _details);
  }

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.selectedTarget;
    final hasTarget = target != null;
    final canUseSelectedTarget =
        hasTarget && _locationChoice != _LocationChoice.wherever;
    final isEditing = widget.initialStep != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit activity' : 'Add activity'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in const [
                  ItineraryStepType.shop,
                  ItineraryStepType.eat,
                  ItineraryStepType.party,
                  ItineraryStepType.walk,
                  ItineraryStepType.sightsee,
                  ItineraryStepType.meander,
                ])
                  _ActivityTypeChip(
                    type: type,
                    selected: _type == type,
                    onSelected: _selectActivityType,
                  ),
                _ActivityTypeChip(
                  type: ItineraryStepType.exactLocation,
                  selected: _type == ItineraryStepType.exactLocation,
                  onSelected: (type) {
                    setState(() {
                      _type = type;
                      _locationChoice = _LocationChoice.exactSelected;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _detailsController,
              decoration: InputDecoration(
                labelText: 'Extra info',
                hintText: _type.detailHint,
                border: const OutlineInputBorder(),
              ),
              minLines: 1,
              maxLines: 3,
              onChanged: (value) => _details = value,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _durationMinutes,
              decoration: const InputDecoration(
                labelText: 'Duration',
                border: OutlineInputBorder(),
              ),
              items: _activityDurationOptions
                  .map(
                    (duration) => DropdownMenuItem(
                      value: duration,
                      child: Text(_DurationMenu._durationLabel(duration)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _durationMinutes = value);
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _LocationChoiceChip(
                  choice: _LocationChoice.wherever,
                  selected: _locationChoice == _LocationChoice.wherever,
                  enabled: _type != ItineraryStepType.exactLocation,
                  icon: Icons.travel_explore,
                  label: 'Wherever',
                  onSelected: _selectLocationChoice,
                ),
                _LocationChoiceChip(
                  choice: _LocationChoice.aroundSelected,
                  selected: _locationChoice == _LocationChoice.aroundSelected,
                  icon: Icons.my_location,
                  label: 'Around here',
                  onSelected: _selectLocationChoice,
                ),
                _LocationChoiceChip(
                  choice: _LocationChoice.areaSelected,
                  selected: _locationChoice == _LocationChoice.areaSelected,
                  icon: Icons.radio_button_unchecked,
                  label: 'Area',
                  onSelected: _selectLocationChoice,
                ),
                _LocationChoiceChip(
                  choice: _LocationChoice.exactSelected,
                  selected: _locationChoice == _LocationChoice.exactSelected,
                  icon: Icons.place,
                  label: 'Exact',
                  onSelected: _selectLocationChoice,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (canUseSelectedTarget)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_selectedTargetResult(target)),
            child: const Text('Selected'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_primaryResult()),
          child: Text(
            _locationChoice == _LocationChoice.wherever
                ? isEditing
                      ? 'Save'
                      : 'Add'
                : 'Pick where',
          ),
        ),
      ],
    );
  }

  void _selectLocationChoice(_LocationChoice choice) {
    setState(() => _locationChoice = choice);
  }

  void _selectActivityType(ItineraryStepType type) {
    setState(() => _type = type);
  }

  _ActivityDialogResult _primaryResult() {
    final existingLocation = widget.initialStep?.location;
    return switch (_locationChoice) {
      _LocationChoice.wherever => _ActivityDialogResult.insert(
        type: _type,
        details: _details,
        durationMinutes: _durationMinutes,
        location: LocationConstraint.wherever(),
      ),
      _LocationChoice.aroundSelected
          when existingLocation?.type == LocationConstraintType.aroundPoint =>
        _ActivityDialogResult.insert(
          type: _type,
          details: _details,
          durationMinutes: _durationMinutes,
          location: existingLocation!,
        ),
      _LocationChoice.areaSelected
          when existingLocation?.type == LocationConstraintType.areaCircle =>
        _ActivityDialogResult.insert(
          type: _type,
          details: _details,
          durationMinutes: _durationMinutes,
          location: existingLocation!,
        ),
      _LocationChoice.exactSelected
          when existingLocation?.type == LocationConstraintType.exactPoint =>
        _ActivityDialogResult.insert(
          type: _type,
          details: _details,
          durationMinutes: _durationMinutes,
          location: existingLocation!,
        ),
      _LocationChoice.aroundSelected => _ActivityDialogResult.pickOnMap(
        type: _type,
        details: _details,
        durationMinutes: _durationMinutes,
        pickKind: TripLocationPickKind.aroundPoint,
      ),
      _LocationChoice.areaSelected => _ActivityDialogResult.pickOnMap(
        type: _type,
        details: _details,
        durationMinutes: _durationMinutes,
        pickKind: TripLocationPickKind.areaCircle,
      ),
      _LocationChoice.exactSelected => _ActivityDialogResult.pickOnMap(
        type: _type,
        details: _details,
        durationMinutes: _durationMinutes,
        pickKind: TripLocationPickKind.exactPoint,
      ),
    };
  }

  _ActivityDialogResult _selectedTargetResult(SelectedMapTarget target) {
    final point = target.toGeoCoordinate();
    return switch (_locationChoice) {
      _LocationChoice.wherever => _primaryResult(),
      _LocationChoice.aroundSelected => _ActivityDialogResult.insert(
        type: _type,
        details: _details,
        durationMinutes: _durationMinutes,
        location: LocationConstraint.aroundPoint(point),
      ),
      _LocationChoice.areaSelected => _ActivityDialogResult.pickOnMap(
        type: _type,
        details: _details,
        durationMinutes: _durationMinutes,
        pickKind: TripLocationPickKind.areaCircle,
        areaCenter: point,
      ),
      _LocationChoice.exactSelected => _ActivityDialogResult.insert(
        type: _type,
        details: _details,
        durationMinutes: _durationMinutes,
        location: LocationConstraint.exactPoint(point),
      ),
    };
  }
}

enum _LocationChoice { wherever, aroundSelected, areaSelected, exactSelected }

class _ActivityTypeChip extends StatelessWidget {
  const _ActivityTypeChip({
    required this.type,
    required this.selected,
    required this.onSelected,
  });

  final ItineraryStepType type;
  final bool selected;
  final ValueChanged<ItineraryStepType> onSelected;

  @override
  Widget build(BuildContext context) {
    final color = Color(type.colorValue);
    final theme = Theme.of(context);
    return ChoiceChip(
      avatar: Icon(
        _stepIcon(type),
        size: 18,
        color: selected ? color : color.withValues(alpha: 0.88),
      ),
      label: Text(type.defaultTitle, softWrap: false),
      selected: selected,
      showCheckmark: false,
      backgroundColor: color.withValues(alpha: 0.10),
      selectedColor: color.withValues(alpha: 0.22),
      side: BorderSide(
        color: selected
            ? color.withValues(alpha: 0.85)
            : color.withValues(alpha: 0.35),
      ),
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        color: selected ? color : theme.colorScheme.onSurface,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      onSelected: (_) => onSelected(type),
    );
  }
}

class _LocationChoiceChip extends StatelessWidget {
  const _LocationChoiceChip({
    required this.choice,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onSelected,
    this.enabled = true,
  });

  final _LocationChoice choice;
  final bool selected;
  final IconData icon;
  final String label;
  final ValueChanged<_LocationChoice> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      avatar: Icon(icon, size: 18),
      label: Text(label, softWrap: false),
      selected: selected,
      onSelected: enabled ? (_) => onSelected(choice) : null,
    );
  }
}

class _ActivityDialogResult {
  const _ActivityDialogResult._({
    required this.type,
    required this.details,
    required this.durationMinutes,
    this.location,
    this.pickKind,
    this.areaCenter,
    this.radiusMeters = 500,
  });

  factory _ActivityDialogResult.insert({
    required ItineraryStepType type,
    required String details,
    required int durationMinutes,
    required LocationConstraint location,
  }) {
    return _ActivityDialogResult._(
      type: type,
      details: details,
      durationMinutes: durationMinutes,
      location: location,
    );
  }

  factory _ActivityDialogResult.pickOnMap({
    required ItineraryStepType type,
    required String details,
    required int durationMinutes,
    required TripLocationPickKind pickKind,
    GeoCoordinate? areaCenter,
    double radiusMeters = 500,
  }) {
    return _ActivityDialogResult._(
      type: type,
      details: details,
      durationMinutes: durationMinutes,
      pickKind: pickKind,
      areaCenter: areaCenter,
      radiusMeters: radiusMeters,
    );
  }

  final ItineraryStepType type;
  final String details;
  final int durationMinutes;
  final LocationConstraint? location;
  final TripLocationPickKind? pickKind;
  final GeoCoordinate? areaCenter;
  final double radiusMeters;
}

extension on SelectedMapTarget {
  GeoCoordinate toGeoCoordinate() {
    if (isWaypoint) {
      return GeoCoordinate(
        lat: coordinates.latitude,
        lon: coordinates.longitude,
      );
    }
    final label =
        '$name (${coordinates.latitude.toStringAsFixed(6)}, '
        '${coordinates.longitude.toStringAsFixed(6)})';
    return GeoCoordinate(
      lat: coordinates.latitude,
      lon: coordinates.longitude,
      label: label,
    );
  }
}

String _coordinateLabel(GeoCoordinate coordinate) {
  return coordinate.label ?? coordinate.coordinateLabel;
}

String _locationConstraintLabel(LocationConstraint location) {
  return switch (location.type) {
    LocationConstraintType.exactPoint =>
      location.point == null
          ? 'Pick location'
          : _coordinateLabel(location.point!),
    LocationConstraintType.aroundPoint =>
      location.point == null
          ? 'Pick location'
          : 'Around ${_coordinateLabel(location.point!)}',
    LocationConstraintType.areaCircle =>
      location.center == null
          ? 'Pick area'
          : '${_coordinateLabel(location.center!)} / '
                '${_radiusLabel(location.radiusMeters ?? 500)}',
    LocationConstraintType.wherever => 'Wherever',
  };
}

_LocationChoice _locationChoiceForLocation(LocationConstraint location) {
  return switch (location.type) {
    LocationConstraintType.exactPoint => _LocationChoice.exactSelected,
    LocationConstraintType.aroundPoint => _LocationChoice.aroundSelected,
    LocationConstraintType.areaCircle => _LocationChoice.areaSelected,
    LocationConstraintType.wherever => _LocationChoice.wherever,
  };
}

TripLocationPickKind? _pickKindForLocation(LocationConstraint location) {
  return switch (location.type) {
    LocationConstraintType.exactPoint => TripLocationPickKind.exactPoint,
    LocationConstraintType.aroundPoint => TripLocationPickKind.aroundPoint,
    LocationConstraintType.areaCircle => TripLocationPickKind.areaCircle,
    LocationConstraintType.wherever => null,
  };
}

IconData _stepIcon(ItineraryStepType type) {
  return switch (type) {
    ItineraryStepType.shop => Icons.shopping_bag,
    ItineraryStepType.eat => Icons.restaurant,
    ItineraryStepType.party => Icons.nightlife,
    ItineraryStepType.walk => Icons.directions_walk,
    ItineraryStepType.sightsee => Icons.photo_camera,
    ItineraryStepType.meander => Icons.auto_awesome,
    ItineraryStepType.exactLocation => Icons.place,
  };
}

String _radiusLabel(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}
