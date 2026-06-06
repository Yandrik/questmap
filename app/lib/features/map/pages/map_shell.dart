import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/app_config.dart';
import '../model/rendered_map_feature.dart';
import '../model/selected_map_target.dart';
import '../services/map_feature_hit_tester.dart';
import '../services/map_icon_registry.dart';
import '../services/map_selection_overlay.dart';
import '../services/map_style_config.dart';
import '../widgets/location_button.dart';
import '../widgets/map_title_badge.dart';
import '../widgets/target_details_panel.dart';

class MapShell extends StatefulWidget {
  const MapShell({super.key});

  @override
  State<MapShell> createState() => _MapShellState();
}

class _MapShellState extends State<MapShell> {
  static const _mapControlSpacing = 10.0;
  static const _mapControlMargin = 12.0;
  static const _topMapOrnamentMargin = 12.0;

  final _hitTester = const MapFeatureHitTester();
  final _iconRegistry = const MapIconRegistry();
  final _selectionOverlay = MapSelectionOverlay();

  MapLibreMapController? _controller;
  SelectedMapTarget? _selectedTarget;
  LatLng? _lastUserLocation;
  PermissionStatus? _locationPermissionStatus;
  bool _isQuerying = false;
  bool _isRequestingLocation = false;
  bool _isUserLocationEnabled = false;
  bool _hasCenteredOnUserLocation = false;
  String? _message;

  bool get _supportsUserLocation {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestUserLocationPermission();
    });
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
  }

  Future<void> _onStyleLoaded() async {
    final controller = _controller;
    if (controller == null) return;

    await _iconRegistry.registerStyleIcons(controller);
    await _selectionOverlay.addSelectionLayer(controller);

    final selectedTarget = _selectedTarget;
    if (selectedTarget != null) {
      await _selectionOverlay.setSelectionCircle(
        selectedTarget.coordinates,
        controller,
      );
    }
  }

  Future<void> _onMapClick(math.Point<double> point, LatLng coordinates) async {
    final controller = _controller;
    if (controller == null) return;

    setState(() {
      _isQuerying = true;
      _message = null;
    });

    final features = await controller.queryRenderedFeaturesInRect(
      ui.Rect.fromLTRB(point.x - 8, point.y - 8, point.x + 8, point.y + 8),
      MapStyleConfig.interactiveLayerIds,
      null,
    );

    if (!mounted) return;

    final renderedFeatures = features
        .whereType<Map>()
        .map(RenderedMapFeature.fromFeature)
        .toList();
    final nearestFeature = await _hitTester.nearestFeature(
      tapPoint: point,
      features: renderedFeatures,
      controller: controller,
    );
    final selectedTarget = nearestFeature == null
        ? SelectedMapTarget.waypoint(coordinates: coordinates)
        : SelectedMapTarget.feature(
            feature: nearestFeature,
            fallbackCoordinates: coordinates,
          );

    if (nearestFeature == null) {
      await _selectionOverlay.setWaypointMarker(coordinates, controller);
    } else {
      await _selectionOverlay.setWaypointMarker(null, controller);
    }
    await _selectionOverlay.setSelectionCircle(
      selectedTarget.coordinates,
      controller,
    );

    if (!mounted) return;

    setState(() {
      _isQuerying = false;
      _selectedTarget = selectedTarget;
      _message = null;
    });
  }

  Future<void> _requestUserLocationPermission() async {
    if (!_supportsUserLocation) {
      if (!mounted) return;
      setState(() {
        _message = 'User location is not supported on this platform.';
      });
      return;
    }

    setState(() {
      _isRequestingLocation = true;
      _message = 'Requesting location permission...';
    });

    try {
      if (!kIsWeb) {
        final serviceStatus = await Permission.locationWhenInUse.serviceStatus;
        if (serviceStatus.isDisabled) {
          if (!mounted) return;
          setState(() {
            _isRequestingLocation = false;
            _isUserLocationEnabled = false;
            _message = 'Turn on location services to show your position.';
          });
          return;
        }
      }

      final status = await Permission.locationWhenInUse.request();
      if (!mounted) return;

      final isGranted = status.isGranted || status.isLimited;
      setState(() {
        _locationPermissionStatus = status;
        _isRequestingLocation = false;
        _isUserLocationEnabled = isGranted;
        _hasCenteredOnUserLocation = false;
        _message = isGranted
            ? 'Showing your location.'
            : status.isPermanentlyDenied
            ? 'Location permission is disabled. Open settings to enable it.'
            : 'Location permission was denied.';
      });

      if (isGranted) {
        await _goToUserLocation();
      }
    } on Exception {
      if (!mounted) return;
      setState(() {
        _isRequestingLocation = false;
        _isUserLocationEnabled = false;
        _message = 'Location permission is unavailable right now.';
      });
    }
  }

  Future<void> _openLocationSettings() async {
    await openAppSettings();
  }

  Future<void> _goToUserLocation() async {
    final controller = _controller;
    if (controller == null || !_isUserLocationEnabled) return;

    final location =
        _lastUserLocation ?? await controller.requestMyLocationLatLng();
    if (!mounted) return;

    if (location == null) {
      setState(() {
        _message = 'Waiting for your current location...';
      });
      return;
    }

    await controller.animateCamera(CameraUpdate.newLatLngZoom(location, 16));
  }

  Future<void> _zoomIn() async {
    await _controller?.animateCamera(CameraUpdate.zoomIn());
  }

  Future<void> _zoomOut() async {
    await _controller?.animateCamera(CameraUpdate.zoomOut());
  }

  void _onUserLocationUpdated(UserLocation location) {
    final shouldCenter = !_hasCenteredOnUserLocation;
    _lastUserLocation = location.position;

    if (mounted) {
      setState(() {
        _hasCenteredOnUserLocation = true;
      });
    }

    if (shouldCenter) {
      _goToUserLocation();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= 720;
    final topOrnamentInset = media.padding.top + _topMapOrnamentMargin;
    final bottomControlInset = isWide
        ? media.padding.bottom + _mapControlMargin
        : media.size.height * 0.26 + _mapControlMargin;

    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            styleString: mapStyleAsset,
            initialCameraPosition: MapStyleConfig.initialCameraPosition,
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            onMapClick: _onMapClick,
            onUserLocationUpdated: _onUserLocationUpdated,
            compassEnabled: true,
            compassViewPosition: CompassViewPosition.topRight,
            compassViewMargins: math.Point(_mapControlMargin, topOrnamentInset),
            logoEnabled: true,
            logoViewPosition: LogoViewPosition.bottomLeft,
            logoViewMargins: const math.Point(12, 12),
            trackCameraPosition: true,
            myLocationEnabled: _isUserLocationEnabled,
            myLocationTrackingMode: _isUserLocationEnabled
                ? MyLocationTrackingMode.tracking
                : MyLocationTrackingMode.none,
            myLocationRenderMode: _isUserLocationEnabled
                ? MyLocationRenderMode.compass
                : MyLocationRenderMode.normal,
            attributionButtonPosition: isWide
                ? AttributionButtonPosition.bottomLeft
                : AttributionButtonPosition.topLeft,
            attributionButtonMargins: math.Point(
              _mapControlMargin,
              isWide ? _mapControlMargin : topOrnamentInset,
            ),
          ),
          const MapTitleBadge(),
          Positioned(
            right: _mapControlMargin,
            bottom: bottomControlInset,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: _mapControlMargin),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MapZoomButton(
                    heroTag: 'meander-zoom-in',
                    tooltip: 'Zoom in',
                    icon: Icons.add,
                    onPressed: _zoomIn,
                  ),
                  const SizedBox(height: _mapControlSpacing),
                  _MapZoomButton(
                    heroTag: 'meander-zoom-out',
                    tooltip: 'Zoom out',
                    icon: Icons.remove,
                    onPressed: _zoomOut,
                  ),
                  const SizedBox(height: _mapControlSpacing),
                  LocationButton(
                    isRequesting: _isRequestingLocation,
                    isLocationEnabled: _isUserLocationEnabled,
                    isPermanentlyDenied:
                        _locationPermissionStatus?.isPermanentlyDenied ?? false,
                    onRequest: _requestUserLocationPermission,
                    onRecenter: _goToUserLocation,
                    onOpenSettings: _openLocationSettings,
                  ),
                ],
              ),
            ),
          ),
          if (isWide)
            Positioned(
              top: 12,
              right: 12,
              bottom: 12,
              width: 360,
              child: TargetDetailsPanel(
                selectedTarget: _selectedTarget,
                isQuerying: _isQuerying,
                message: _message,
              ),
            )
          else
            Positioned.fill(
              child: SafeArea(
                top: false,
                child: DraggableScrollableSheet(
                  minChildSize: 0.18,
                  initialChildSize: 0.26,
                  maxChildSize: 0.5,
                  snap: true,
                  snapSizes: const [0.26, 0.5],
                  builder: (context, scrollController) => TargetDetailsPanel(
                    selectedTarget: _selectedTarget,
                    isQuerying: _isQuerying,
                    message: _message,
                    compact: true,
                    scrollController: scrollController,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MapZoomButton extends StatelessWidget {
  const _MapZoomButton({
    required this.heroTag,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String heroTag;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: FloatingActionButton.small(
        heroTag: heroTag,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.primary,
        onPressed: onPressed,
        child: Icon(icon),
      ),
    );
  }
}
