import 'dart:async';

import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

import '../../../_shared/models/geo_coordinate.dart';
import '../../../_shared/models/transport_mode.dart';
import '../manager/trip_plan_manager.dart';
import '../model/location_constraint.dart';
import '../model/trip_plan.dart';

class ActiveTripCard extends WatchingStatefulWidget {
  const ActiveTripCard({super.key});

  @override
  State<ActiveTripCard> createState() => _ActiveTripCardState();
}

class _ActiveTripCardState extends State<ActiveTripCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = watchIt<TripPlanManager>();
    final item = manager.currentItem;
    if (!manager.isTripActive || item == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          elevation: 5,
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: item.type == TripPlanItemType.travel
                ? _TravelContent(item: item, manager: manager)
                : _ActivityContent(item: item, manager: manager),
          ),
        ),
      ),
    );
  }
}

class _TravelContent extends StatelessWidget {
  const _TravelContent({required this.item, required this.manager});

  final TripPlanItem item;
  final TripPlanManager manager;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final destination = manager.destinationForCurrentTravel;
    final transitSegments = item.segments
        .where((segment) => segment.transitDetails != null)
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _modeIcon(item.transportMode),
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _ModePill(mode: item.transportMode),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          destination == null
              ? item.description
              : 'Next: ${_coordinateLabel(destination)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        if (item.description.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            item.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (transitSegments.isNotEmpty) ...[
          const SizedBox(height: 10),
          _TravelTransitLegs(segments: transitSegments),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: manager.stopTrip,
                icon: const Icon(Icons.stop),
                label: const Text('End'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: manager.markArrived,
                icon: const Icon(Icons.flag),
                label: const Text('Arrived'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TravelTransitLegs extends StatelessWidget {
  const _TravelTransitLegs({required this.segments});

  final List<TripRouteSegment> segments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < segments.length; index++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _modeIcon(segments[index].transportMode),
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _segmentTitle(segments[index]),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_segmentMeta(segments[index]) case final meta?) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (_segmentStopCount(segments[index])
                        case final stops?) ...[
                      const SizedBox(height: 2),
                      Text(
                        stops,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (index != segments.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ActivityContent extends StatelessWidget {
  const _ActivityContent({required this.item, required this.manager});

  final TripPlanItem item;
  final TripPlanManager manager;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(item.stepType?.colorValue ?? 0xFF14B8A6);
    final duration = _activityDuration(item);
    final startedAt = manager.activeActivityStartedAt;
    final remaining = startedAt == null
        ? duration
        : duration - DateTime.now().toUtc().difference(startedAt);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SizedBox.square(
                dimension: 38,
                child: Icon(Icons.place, color: color),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _remainingLabel(remaining),
                    style: theme.textTheme.labelLarge?.copyWith(color: color),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (item.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            item.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 6),
        Text(
          _targetLabel(item.visualTarget, item.location),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: manager.completeCurrentActivity,
            icon: const Icon(Icons.check),
            label: const Text('Complete'),
          ),
        ),
      ],
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({required this.mode});

  final TransportMode? mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          mode?.displayLabel ?? 'Route',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

Duration _activityDuration(TripPlanItem item) {
  final start = item.startTime;
  final end = item.endTime;
  if (start == null || end == null || !end.isAfter(start)) {
    return const Duration(minutes: 30);
  }
  return end.difference(start);
}

String _remainingLabel(Duration remaining) {
  if (remaining.isNegative) return '0 min left';
  final minutes = (remaining.inSeconds / 60).ceil();
  if (minutes < 60) return '$minutes min left';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h left' : '${hours}h ${rest}m left';
}

String _targetLabel(LocationConstraint? target, GeoCoordinate? location) {
  if (target == null) {
    return location == null
        ? 'Location details unavailable'
        : _coordinateLabel(location);
  }
  return switch (target.type) {
    LocationConstraintType.exactPoint =>
      'Exact location: ${_coordinateLabel(target.point ?? location)}',
    LocationConstraintType.aroundPoint =>
      'Around ${_coordinateLabel(target.point ?? location)}',
    LocationConstraintType.areaCircle =>
      'Area near ${_coordinateLabel(target.center ?? location)}, ${_radiusLabel(target.radiusMeters ?? 500)}',
    LocationConstraintType.wherever =>
      location == null ? 'Flexible location' : _coordinateLabel(location),
  };
}

String _coordinateLabel(GeoCoordinate? coordinate) {
  if (coordinate == null) return 'Unknown location';
  return coordinate.label ?? coordinate.coordinateLabel;
}

String _radiusLabel(double meters) {
  if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
  return '${meters.round()} m';
}

String _segmentTitle(TripRouteSegment segment) {
  final details = segment.transitDetails;
  final from = details?.fromLabel ?? 'Start';
  final to = details?.toLabel ?? 'Destination';
  if (segment.transportMode == TransportMode.walk) {
    return 'Walk to $to';
  }
  if (segment.transportMode == TransportMode.publicTransport) {
    final vehicle = _vehicleLabel(segment);
    final toward = details?.headsign == null
        ? ''
        : ' toward ${details!.headsign}';
    return 'Take $vehicle$toward from $from; get off at $to';
  }
  final verb = switch (segment.transportMode) {
    TransportMode.bike => 'Bike',
    TransportMode.drive => 'Drive',
    TransportMode.walk => 'Walk',
    TransportMode.publicTransport => 'Take transit',
  };
  return '$verb to $to';
}

String _vehicleLabel(TripRouteSegment segment) {
  final details = segment.transitDetails;
  final name = details?.vehicleLabel;
  final type = details?.vehicleType;
  if (type == null || type.isEmpty) {
    return name ?? segment.transportMode.displayLabel;
  }
  if (name == null || name.isEmpty) return type;
  if (name.toLowerCase().contains(type.toLowerCase())) return name;
  return '$type $name';
}

String? _segmentMeta(TripRouteSegment segment) {
  final details = segment.transitDetails;
  if (details == null) return segment.description;
  final timing = _timeRange(details.startTime, details.endTime);
  final status = details.cancelled == true
      ? 'Cancelled'
      : details.realTime == true
      ? 'Realtime'
      : null;
  final values = [?timing, ?status, ?segment.description];
  if (values.isEmpty) return null;
  return values.join(' · ');
}

String? _segmentStopCount(TripRouteSegment segment) {
  final stops = segment.transitDetails?.intermediateStopLabels;
  if (stops == null || stops.isEmpty) return null;
  return '${stops.length} intermediate stops';
}

String? _timeRange(DateTime? start, DateTime? end) {
  if (start == null && end == null) return null;
  if (start == null) return 'Arrive ${_timeLabel(end!)}';
  if (end == null) return 'Depart ${_timeLabel(start)}';
  return '${_timeLabel(start)}-${_timeLabel(end)}';
}

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

IconData _modeIcon(TransportMode? mode) {
  return switch (mode) {
    TransportMode.walk => Icons.directions_walk,
    TransportMode.bike => Icons.directions_bike,
    TransportMode.drive => Icons.directions_car,
    TransportMode.publicTransport => Icons.directions_transit,
    null => Icons.route,
  };
}
