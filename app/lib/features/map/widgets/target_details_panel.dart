import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../model/selected_map_target.dart';
import '../services/map_icon_catalog.dart';

class TargetDetailsPanel extends StatelessWidget {
  const TargetDetailsPanel({
    required this.selectedTarget,
    required this.isQuerying,
    required this.message,
    this.compact = false,
    this.scrollController,
    super.key,
  });

  final SelectedMapTarget? selectedTarget;
  final bool isQuerying;
  final String? message;
  final bool compact;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
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
                            const SizedBox(height: 12),
                          ],
                        ),
                ),
                if (selectedTarget != null)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Navigation target: ${selectedTarget!.name}',
                            ),
                          ),
                        );
                      },
                      child: const Text('Navigate to'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
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
