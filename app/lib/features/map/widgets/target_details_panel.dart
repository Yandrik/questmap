import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../_shared/models/transport_mode.dart';
import '../../routing/model/navigation_candidate.dart';
import '../model/selected_map_target.dart';
import '../services/map_icon_catalog.dart';

class TargetDetailsPanel extends StatelessWidget {
  const TargetDetailsPanel({
    required this.selectedTarget,
    required this.isQuerying,
    required this.message,
    required this.routeCandidates,
    required this.selectedRoute,
    required this.isRouting,
    required this.isNavigationActive,
    required this.onNavigate,
    required this.onTrip,
    required this.onSelectRoute,
    required this.onStartNavigation,
    required this.onStopNavigation,
    this.compact = false,
    this.scrollController,
    super.key,
  });

  final SelectedMapTarget? selectedTarget;
  final bool isQuerying;
  final String? message;
  final List<NavigationCandidate> routeCandidates;
  final NavigationCandidate? selectedRoute;
  final bool isRouting;
  final bool isNavigationActive;
  final VoidCallback onNavigate;
  final VoidCallback onTrip;
  final ValueChanged<String> onSelectRoute;
  final VoidCallback onStartNavigation;
  final VoidCallback onStopNavigation;
  final bool compact;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transitItineraryRoute = _transitItineraryRoute(selectedRoute);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 8 : 0, 0, compact ? 8 : 0, 8),
        child: Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surface,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, compact ? 8 : 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (compact) const _SheetHandle(),
                _PanelHeader(target: selectedTarget, isQuerying: isQuerying),
                if (selectedTarget != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    selectedTarget!.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: selectedTarget == null
                      ? _EmptyFeatureState(
                          message: message,
                          scrollController: scrollController,
                        )
                      : ListView(
                          controller: scrollController,
                          padding: EdgeInsets.zero,
                          children: [
                            if (!selectedTarget!.isWaypoint)
                              _TargetDetails(target: selectedTarget!),
                            if (routeCandidates.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _RouteCandidateList(
                                candidates: routeCandidates,
                                selectedRoute: selectedRoute,
                                onSelectRoute: onSelectRoute,
                              ),
                            ],
                            if (transitItineraryRoute != null) ...[
                              const SizedBox(height: 8),
                              _TransitItinerarySection(
                                route: transitItineraryRoute,
                                isNavigationActive: isNavigationActive,
                              ),
                            ],
                            const SizedBox(height: 12),
                          ],
                        ),
                ),
                if (selectedTarget != null)
                  _PanelActions(
                    isRouting: isRouting,
                    isNavigationActive: isNavigationActive,
                    hasRoute: selectedRoute != null,
                    onNavigate: onNavigate,
                    onTrip: onTrip,
                    onStartNavigation: onStartNavigation,
                    onStopNavigation: onStopNavigation,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelActions extends StatelessWidget {
  const _PanelActions({
    required this.isRouting,
    required this.isNavigationActive,
    required this.hasRoute,
    required this.onNavigate,
    required this.onTrip,
    required this.onStartNavigation,
    required this.onStopNavigation,
  });

  final bool isRouting;
  final bool isNavigationActive;
  final bool hasRoute;
  final VoidCallback onNavigate;
  final VoidCallback onTrip;
  final VoidCallback onStartNavigation;
  final VoidCallback onStopNavigation;

  @override
  Widget build(BuildContext context) {
    if (isNavigationActive) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: _filledStyle(context),
          onPressed: onStopNavigation,
          icon: const Icon(Icons.stop),
          label: const Text('Stop navigation'),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: _filledStyle(context),
                onPressed: isRouting ? null : onNavigate,
                icon: isRouting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.near_me),
                label: const Text('Navigate to'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: onTrip,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Trip'),
              ),
            ),
          ],
        ),
        if (hasRoute) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: _filledStyle(context),
              onPressed: onStartNavigation,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start navigation'),
            ),
          ),
        ],
      ],
    );
  }

  static ButtonStyle _filledStyle(BuildContext context) {
    return FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class _RouteCandidateList extends StatelessWidget {
  const _RouteCandidateList({
    required this.candidates,
    required this.selectedRoute,
    required this.onSelectRoute,
  });

  final List<NavigationCandidate> candidates;
  final NavigationCandidate? selectedRoute;
  final ValueChanged<String> onSelectRoute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Routes',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        for (final candidate in candidates) ...[
          _RouteCandidateTile(
            candidate: candidate,
            isSelected: candidate.id == selectedRoute?.id,
            onTap: () => onSelectRoute(candidate.id),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _RouteCandidateTile extends StatelessWidget {
  const _RouteCandidateTile({
    required this.candidate,
    required this.isSelected,
    required this.onTap,
  });

  final NavigationCandidate candidate;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.36,
                ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(_modeIcon(candidate.mode), color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.mode.displayLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      candidate.summaryLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected) const Icon(Icons.check_circle, size: 20),
            ],
          ),
        ),
      ),
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

class _TransitItinerarySection extends StatelessWidget {
  const _TransitItinerarySection({
    required this.route,
    required this.isNavigationActive,
  });

  final NavigationCandidate route;
  final bool isNavigationActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.directions_transit,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isNavigationActive
                        ? 'Transit navigation'
                        : 'Transit itinerary',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  route.durationLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _RouteLegList(legs: route.legs),
          ],
        ),
      ),
    );
  }
}

class _RouteLegList extends StatelessWidget {
  const _RouteLegList({required this.legs});

  final List<NavigationLeg> legs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < legs.length; index++)
            _RouteLegRow(
              leg: legs[index],
              isLast: index == legs.length - 1,
              index: index + 1,
            ),
        ],
      ),
    );
  }
}

class _RouteLegRow extends StatelessWidget {
  const _RouteLegRow({
    required this.leg,
    required this.isLast,
    required this.index,
  });

  final NavigationLeg leg;
  final bool isLast;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = leg.transitDetails;
    final title = _legTitle(leg);
    final timing = _timeRange(details?.startTime, details?.endTime);
    final status = _statusLabel(details?.realTime, details?.cancelled);
    final distance = leg.distanceMeters == null
        ? null
        : _distanceLabel(leg.distanceMeters!);
    final stopCount =
        details != null && details.intermediateStopLabels.isNotEmpty
        ? '${details.intermediateStopLabels.length} intermediate stops'
        : null;
    final meta = [
      ?timing,
      ?status,
      _durationLabel(leg.durationSeconds),
      ?distance,
    ].join(' · ');
    final notes = [
      ?details?.agencyName,
      ?stopCount,
      ...?details?.instructions.take(2),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: SizedBox.square(
                dimension: 28,
                child: Center(
                  child: Text(
                    '$index',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            if (!isLast)
              SizedBox(
                width: 1,
                height: notes.isEmpty ? 38 : 68,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _modeIcon(leg.mode),
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                for (final note in notes) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;

    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const SizedBox(width: 44, height: 4),
        ),
      ),
    );
  }
}

String _legTitle(NavigationLeg leg) {
  final details = leg.transitDetails;
  final from = details?.fromLabel ?? leg.fromLabel;
  final to = details?.toLabel ?? leg.toLabel;
  if (leg.mode == TransportMode.walk) {
    return 'Walk to $to';
  }
  if (leg.mode == TransportMode.publicTransport) {
    final vehicle = _vehicleLabel(leg);
    final toward = details?.headsign == null
        ? ''
        : ' toward ${details!.headsign}';
    return 'Take $vehicle$toward from $from; get off at $to';
  }
  final verb = switch (leg.mode) {
    TransportMode.bike => 'Bike',
    TransportMode.drive => 'Drive',
    TransportMode.walk => 'Walk',
    TransportMode.publicTransport => 'Take transit',
  };
  return '$verb to $to';
}

String _vehicleLabel(NavigationLeg leg) {
  final details = leg.transitDetails;
  final name = details?.vehicleLabel ?? leg.displayName;
  final type = details?.vehicleType;
  if (type == null || type.isEmpty) {
    return name ?? leg.mode.displayLabel;
  }
  if (name == null || name.isEmpty) return type;
  if (name.toLowerCase().contains(type.toLowerCase())) return name;
  return '$type $name';
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

String? _statusLabel(bool? realTime, bool? cancelled) {
  if (cancelled == true) return 'Cancelled';
  if (realTime == true) return 'Realtime';
  return null;
}

String _durationLabel(int durationSeconds) {
  final minutes = (durationSeconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}min';
}

String _distanceLabel(double distanceMeters) {
  if (distanceMeters >= 1000) {
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }
  return '${distanceMeters.round()} m';
}

IconData _modeIcon(TransportMode mode) {
  return switch (mode) {
    TransportMode.walk => Icons.directions_walk,
    TransportMode.bike => Icons.directions_bike,
    TransportMode.drive => Icons.directions_car,
    TransportMode.publicTransport => Icons.directions_transit,
  };
}

NavigationCandidate? _transitItineraryRoute(NavigationCandidate? route) {
  if (route == null || route.mode != TransportMode.publicTransport) {
    return null;
  }
  if (route.legs.isEmpty) return null;
  return route;
}

class _EmptyFeatureState extends StatelessWidget {
  const _EmptyFeatureState({required this.message, this.scrollController});

  final String? message;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.zero,
      children: [
        SizedBox(
          height: 96,
          child: Center(
            child: Text(
              message ?? 'No point selected.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.target, required this.isQuerying});

  final SelectedMapTarget? target;
  final bool isQuerying;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        _TargetIcon(target: target),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            target?.name ?? 'Map target',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (isQuerying)
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }
}

class _TargetIcon extends StatelessWidget {
  const _TargetIcon({required this.target});

  final SelectedMapTarget? target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feature = target?.feature;
    final iconSvg = feature == null
        ? null
        : MapIconCatalog.styleIcons[MapIconCatalog.iconImageForFeature(
            feature,
          )];

    Widget icon;
    if (iconSvg == null) {
      icon = Icon(
        target == null ? Icons.ads_click : Icons.place,
        color: theme.colorScheme.primary,
        size: 24,
      );
    } else {
      icon = SvgPicture.string(
        iconSvg.replaceAll('currentColor', '#000000'),
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(
          theme.colorScheme.primary,
          BlendMode.srcIn,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox.square(dimension: 40, child: Center(child: icon)),
    );
  }
}

class _TargetDetails extends StatelessWidget {
  const _TargetDetails({required this.target});

  final SelectedMapTarget target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feature = target.feature;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          target.coordinateLabel,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
        if (feature != null && feature.properties.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...feature.properties.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${entry.key}: ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: entry.value),
                  ],
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
