import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

import '../../../_shared/models/geo_coordinate.dart';
import '../../../_shared/models/transport_mode.dart';
import '../../map/model/selected_map_target.dart';
import '../manager/trip_draft_manager.dart';
import '../model/itinerary_step_draft.dart';
import '../model/location_constraint.dart';
import '../model/trip_draft.dart';

class TripComposerPanel extends WatchingWidget {
  const TripComposerPanel({
    required this.onClose,
    this.selectedTarget,
    this.compact = false,
    super.key,
  });

  final VoidCallback onClose;
  final SelectedMapTarget? selectedTarget;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final manager = watchIt<TripDraftManager>();
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
                      _Header(onClose: onClose),
                      const SizedBox(height: 12),
                      _LocationSummary(draft: draft),
                      const SizedBox(height: 12),
                      _TransportModeSelector(draft: draft),
                      const SizedBox(height: 12),
                      Expanded(
                        child: draft.steps.isEmpty
                            ? _EmptyDraftState(
                                onAdd: () => _showActivityDialog(context),
                              )
                            : ListView(
                                padding: EdgeInsets.zero,
                                children: [
                                  for (
                                    var index = 0;
                                    index < draft.steps.length;
                                    index++
                                  ) ...[
                                    _ItineraryStepCard(
                                      step: draft.steps[index],
                                    ),
                                    if (_hasLargeGapAfter(draft.steps, index))
                                      Center(
                                        child: IconButton.filledTonal(
                                          tooltip: 'Add activity',
                                          onPressed: () =>
                                              _showActivityDialog(context),
                                          icon: const Icon(Icons.add),
                                        ),
                                      ),
                                    const SizedBox(height: 10),
                                  ],
                                ],
                              ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _showActivityDialog(context),
                              icon: const Icon(Icons.add),
                              label: const Text('Add activity'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: draft.steps.isEmpty ? null : () {},
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

  Future<void> _showActivityDialog(BuildContext context) async {
    final result = await showDialog<_ActivityDialogResult>(
      context: context,
      builder: (context) =>
          _ActivityPickerDialog(selectedTarget: selectedTarget),
    );
    if (result == null || !context.mounted) return;
    di<TripDraftManager>().addStep(
      type: result.type,
      details: result.details,
      durationMinutes: result.durationMinutes,
      location: result.location,
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
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

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
          tooltip: 'Close',
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _LocationSummary extends StatelessWidget {
  const _LocationSummary({required this.draft});

  final TripDraft draft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Start', style: theme.textTheme.labelMedium),
            Text(
              draft.startLocation.label ?? draft.startLocation.coordinateLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text('End', style: theme.textTheme.labelMedium),
            Text(
              draft.endLocation?.label ??
                  draft.endLocation?.coordinateLabel ??
                  'Optional',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: draft.endLocation == null
                    ? theme.colorScheme.onSurfaceVariant
                    : null,
              ),
            ),
          ],
        ),
      ),
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
  const _ItineraryStepCard({required this.step});

  final ItineraryStepDraft step;

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
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SizedBox.square(
                    dimension: 40,
                    child: Icon(_stepIcon(step.type), color: color),
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

class _DurationMenu extends StatelessWidget {
  const _DurationMenu({required this.step});

  final ItineraryStepDraft step;

  @override
  Widget build(BuildContext context) {
    const durations = [30, 45, 60, 90, 120, 150, 180, 240];
    return DropdownButtonFormField<int>(
      initialValue: durations.contains(step.time.durationMinutes)
          ? step.time.durationMinutes
          : 60,
      decoration: const InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.timer),
        border: OutlineInputBorder(),
      ),
      items: [
        for (final duration in durations)
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
  const _ActivityPickerDialog({required this.selectedTarget});

  final SelectedMapTarget? selectedTarget;

  @override
  State<_ActivityPickerDialog> createState() => _ActivityPickerDialogState();
}

class _ActivityPickerDialogState extends State<_ActivityPickerDialog> {
  ItineraryStepType _type = ItineraryStepType.meander;
  String _details = '';
  int _durationMinutes = 60;
  _LocationChoice _locationChoice = _LocationChoice.wherever;

  @override
  Widget build(BuildContext context) {
    final target = widget.selectedTarget;
    final hasTarget = target != null;

    return AlertDialog(
      title: const Text('Add activity'),
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
                  ChoiceChip(
                    label: Text(type.defaultTitle),
                    selected: _type == type,
                    onSelected: (_) => setState(() => _type = type),
                  ),
                ChoiceChip(
                  label: const Text('Exact location'),
                  selected: _type == ItineraryStepType.exactLocation,
                  onSelected: hasTarget
                      ? (_) => setState(() {
                          _type = ItineraryStepType.exactLocation;
                          _locationChoice = _LocationChoice.exactSelected;
                        })
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
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
              items: const [30, 45, 60, 90, 120, 150, 180, 240]
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
            SegmentedButton<_LocationChoice>(
              segments: [
                const ButtonSegment(
                  value: _LocationChoice.wherever,
                  icon: Icon(Icons.travel_explore),
                  label: Text('Wherever'),
                ),
                ButtonSegment(
                  value: _LocationChoice.aroundSelected,
                  enabled: hasTarget,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Around here'),
                ),
                ButtonSegment(
                  value: _LocationChoice.areaSelected,
                  enabled: hasTarget,
                  icon: const Icon(Icons.radio_button_unchecked),
                  label: const Text('Area'),
                ),
                ButtonSegment(
                  value: _LocationChoice.exactSelected,
                  enabled: hasTarget,
                  icon: const Icon(Icons.place),
                  label: const Text('Exact'),
                ),
              ],
              selected: {_locationChoice},
              onSelectionChanged: (values) {
                setState(() => _locationChoice = values.single);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final location = _locationConstraint();
            if (location == null) return;
            Navigator.of(context).pop(
              _ActivityDialogResult(
                type: _type,
                details: _details,
                durationMinutes: _durationMinutes,
                location: location,
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }

  LocationConstraint? _locationConstraint() {
    final target = widget.selectedTarget;
    return switch (_locationChoice) {
      _LocationChoice.wherever => LocationConstraint.wherever(),
      _LocationChoice.aroundSelected when target != null =>
        LocationConstraint.aroundPoint(target.toGeoCoordinate()),
      _LocationChoice.areaSelected when target != null =>
        LocationConstraint.areaCircle(
          center: target.toGeoCoordinate(),
          radiusMeters: 500,
        ),
      _LocationChoice.exactSelected when target != null =>
        LocationConstraint.exactPoint(target.toGeoCoordinate()),
      _ => null,
    };
  }
}

enum _LocationChoice { wherever, aroundSelected, areaSelected, exactSelected }

class _ActivityDialogResult {
  const _ActivityDialogResult({
    required this.type,
    required this.details,
    required this.durationMinutes,
    required this.location,
  });

  final ItineraryStepType type;
  final String details;
  final int durationMinutes;
  final LocationConstraint location;
}

extension on SelectedMapTarget {
  GeoCoordinate toGeoCoordinate() {
    return GeoCoordinate(
      lat: coordinates.latitude,
      lon: coordinates.longitude,
      label: name,
    );
  }
}
