import 'package:flutter/material.dart';

class LocationButton extends StatelessWidget {
  const LocationButton({
    required this.isRequesting,
    required this.isLocationEnabled,
    required this.isPermanentlyDenied,
    required this.onRequest,
    required this.onRecenter,
    required this.onOpenSettings,
    super.key,
  });

  final bool isRequesting;
  final bool isLocationEnabled;
  final bool isPermanentlyDenied;
  final VoidCallback onRequest;
  final VoidCallback onRecenter;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onPressed = isRequesting
        ? null
        : isPermanentlyDenied
        ? onOpenSettings
        : isLocationEnabled
        ? onRecenter
        : onRequest;

    return Tooltip(
      message: isLocationEnabled
          ? 'Center on your location'
          : isPermanentlyDenied
          ? 'Open location settings'
          : 'Show your location',
      child: FloatingActionButton.small(
        heroTag: 'meander-location',
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.primary,
        onPressed: onPressed,
        child: isRequesting
            ? SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              )
            : Icon(
                isPermanentlyDenied
                    ? Icons.settings
                    : isLocationEnabled
                    ? Icons.my_location
                    : Icons.location_searching,
              ),
      ),
    );
  }
}
