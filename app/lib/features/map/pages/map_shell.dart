import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;
import 'package:watch_it/watch_it.dart';

import '../../../_shared/models/geo_coordinate.dart';
import '../../../_shared/models/transport_mode.dart';
import '../../../app/app_config.dart';
import '../../location/manager/location_manager.dart';
import '../../routing/manager/routing_manager.dart';
import '../../routing/model/direct_navigation_request.dart';
import '../../trip_planning/manager/trip_agent_manager.dart';
import '../../trip_planning/manager/trip_draft_manager.dart';
import '../../trip_planning/manager/trip_plan_manager.dart';
import '../../trip_planning/model/pending_trip_location_pick.dart';
import '../../trip_planning/widgets/trip_composer_panel.dart';
import '../../trip_planning/widgets/trip_planning_overlay.dart';
import '../manager/map_interaction_manager.dart';
import '../manager/map_selection_manager.dart';
import '../model/rendered_map_feature.dart';
import '../model/selected_map_target.dart';
import '../services/map_draft_location_overlay.dart';
import '../services/map_feature_hit_tester.dart';
import '../services/map_icon_registry.dart';
import '../services/map_route_overlay.dart';
import '../services/map_selection_overlay.dart';
import '../services/map_style_config.dart';
import '../widgets/location_button.dart';
import '../widgets/map_title_badge.dart';
import '../widgets/target_details_panel.dart';

class MapShell extends WatchingStatefulWidget {
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
  final _routeOverlay = MapRouteOverlay();
  final _draftLocationOverlay = MapDraftLocationOverlay();

  MapLibreMapController? _controller;
  bool _isTripComposerOpen = false;
  String? _lastDraftLocationPreviewKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestUserLocationPermission();
      di<TripPlanManager>().loadActivePlan();
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
    await _routeOverlay.addRouteLayers(controller);
    await _draftLocationOverlay.addDraftLocationLayers(controller);

    final selectedTarget = di<MapSelectionManager>().selectedTarget;
    if (selectedTarget != null) {
      await _selectionOverlay.setSelectionCircle(
        selectedTarget.coordinates,
        controller,
      );
    }
    await _syncRouteOverlay();
    await _syncDraftLocationOverlay();
  }

  Future<void> _onMapClick(math.Point<double> point, LatLng coordinates) async {
    final controller = _controller;
    if (controller == null) return;

    final draftManager = di<TripDraftManager>();
    if (draftManager.pendingLocationPick != null) {
      await _handleTripLocationPickMapClick(point, coordinates, controller);
      return;
    }

    final selectionManager = di<MapSelectionManager>()..beginQuery();
    final selectedTarget = await _targetForMapTap(
      point: point,
      coordinates: coordinates,
      controller: controller,
    );
    if (!mounted || selectedTarget == null) return;

    if (selectedTarget.isWaypoint) {
      await _selectionOverlay.setWaypointMarker(coordinates, controller);
    } else {
      await _selectionOverlay.setWaypointMarker(null, controller);
    }
    await _selectionOverlay.setSelectionCircle(
      selectedTarget.coordinates,
      controller,
    );
    di<RoutingManager>().clear();
    await _routeOverlay.clear(controller);

    if (!mounted) return;
    selectionManager.selectTarget(selectedTarget);
  }

  Future<SelectedMapTarget?> _targetForMapTap({
    required math.Point<double> point,
    required LatLng coordinates,
    required MapLibreMapController controller,
  }) async {
    final features = await controller.queryRenderedFeaturesInRect(
      ui.Rect.fromLTRB(point.x - 8, point.y - 8, point.x + 8, point.y + 8),
      MapStyleConfig.interactiveLayerIds,
      null,
    );

    if (!mounted) return null;

    final renderedFeatures = features
        .whereType<Map>()
        .map(RenderedMapFeature.fromFeature)
        .toList();
    final nearestFeature = await _hitTester.nearestFeature(
      tapPoint: point,
      features: renderedFeatures,
      controller: controller,
    );
    return nearestFeature == null
        ? SelectedMapTarget.waypoint(coordinates: coordinates)
        : SelectedMapTarget.feature(
            feature: nearestFeature,
            fallbackCoordinates: coordinates,
          );
  }

  Future<void> _handleTripLocationPickMapClick(
    math.Point<double> point,
    LatLng coordinates,
    MapLibreMapController controller,
  ) async {
    final draftManager = di<TripDraftManager>();
    final pending = draftManager.pendingLocationPick;
    if (pending == null) return;

    if (pending.kind.usesArea) {
      draftManager.updatePendingAreaCenter(
        _toGeoCoordinate(coordinates, 'Selected area'),
      );
      await _syncDraftLocationOverlay();
      return;
    }

    final selectedTarget = await _targetForMapTap(
      point: point,
      coordinates: coordinates,
      controller: controller,
    );
    if (!mounted || selectedTarget == null) return;

    draftManager.completePointPick(_targetToGeoCoordinate(selectedTarget));
    di<MapInteractionManager>().setMode(MapInteractionMode.browse);
    await _draftLocationOverlay.clear(controller);
  }

  Future<void> _syncDraftLocationOverlay() async {
    final controller = _controller;
    if (controller == null) return;
    final pending = di<TripDraftManager>().pendingLocationPick;
    if (pending == null) {
      await _draftLocationOverlay.clear(controller);
      return;
    }
    if (pending.kind.usesArea) {
      await _draftLocationOverlay.setArea(
        controller: controller,
        center: pending.areaCenter,
        radiusMeters: pending.radiusMeters,
      );
      return;
    }
    await _draftLocationOverlay.clear(controller);
  }

  void _queueDraftLocationOverlaySync(PendingTripLocationPick? pending) {
    final previewKey = pending == null
        ? 'none'
        : [
            pending.kind.name,
            pending.areaCenter?.lat.toStringAsFixed(7),
            pending.areaCenter?.lon.toStringAsFixed(7),
            pending.radiusMeters.toStringAsFixed(0),
          ].join(':');
    if (_lastDraftLocationPreviewKey == previewKey) return;
    _lastDraftLocationPreviewKey = previewKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_syncDraftLocationOverlay());
    });
  }

  Future<void> _confirmTripAreaPick() async {
    final draftManager = di<TripDraftManager>();
    final pending = draftManager.pendingLocationPick;
    final center = pending?.areaCenter;
    if (pending == null || !pending.kind.usesArea || center == null) return;

    draftManager.completeAreaPick(
      center: center,
      radiusMeters: pending.radiusMeters,
    );
    di<MapInteractionManager>().setMode(MapInteractionMode.browse);
    final controller = _controller;
    if (controller != null) {
      await _draftLocationOverlay.clear(controller);
    }
  }

  Future<void> _cancelTripLocationPick() async {
    di<TripDraftManager>().cancelLocationPick();
    di<MapInteractionManager>().setMode(MapInteractionMode.browse);
    final controller = _controller;
    if (controller != null) {
      await _draftLocationOverlay.clear(controller);
    }
  }

  void _updateTripAreaRadius(double radiusMeters) {
    di<TripDraftManager>().updatePendingAreaRadius(radiusMeters);
    unawaited(_syncDraftLocationOverlay());
  }

  Future<void> _requestUserLocationPermission() async {
    final isGranted = await di<LocationManager>().requestPermission();
    if (isGranted) await _goToUserLocation();
  }

  Future<void> _openLocationSettings() async {
    await openAppSettings();
  }

  Future<void> _goToUserLocation() async {
    final controller = _controller;
    final locationManager = di<LocationManager>();
    if (controller == null || !locationManager.isUserLocationEnabled) return;

    final location =
        _toLatLng(locationManager.lastUserLocation) ??
        await controller.requestMyLocationLatLng();
    if (!mounted) return;

    if (location == null) {
      locationManager.markWaitingForLocation();
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
    final locationManager = di<LocationManager>();
    final shouldCenter = !locationManager.hasCenteredOnUserLocation;
    locationManager.updateUserLocation(_toGeoCoordinate(location.position));

    if (shouldCenter) {
      _goToUserLocation();
    }
  }

  Future<void> _navigateToSelectedTarget() async {
    final target = di<MapSelectionManager>().selectedTarget;
    if (target == null) return;

    final mode = await _showTransportModeSheet();
    if (mode == null) return;

    final start = await _currentStartLocation();
    if (!mounted) return;
    if (start == null) {
      di<MapSelectionManager>().setMessage(
        'Show your location or select a start point before routing.',
      );
      return;
    }

    try {
      await di<RoutingManager>().requestRoutesCommand.runAsync(
        DirectNavigationRequest(
          start: start,
          destination: _toGeoCoordinate(target.coordinates, target.name),
          mode: mode,
        ),
      );
      await _syncRouteOverlay();
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Route failed: $error')));
    }
  }

  Future<TransportMode?> _showTransportModeSheet() {
    return showModalBottomSheet<TransportMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in TransportMode.values)
              ListTile(
                leading: Icon(_transportIcon(mode)),
                title: Text(mode.displayLabel),
                onTap: () => Navigator.of(context).pop(mode),
              ),
          ],
        ),
      ),
    );
  }

  Future<GeoCoordinate?> _currentStartLocation() async {
    final locationManager = di<LocationManager>();
    final known = locationManager.lastUserLocation;
    if (known != null) return known;

    final controller = _controller;
    if (controller == null || !locationManager.isUserLocationEnabled) {
      return null;
    }
    final location = await controller.requestMyLocationLatLng();
    if (location == null) return null;
    final coordinate = _toGeoCoordinate(location);
    locationManager.updateUserLocation(coordinate);
    return coordinate;
  }

  Future<void> _selectRoute(String candidateId) async {
    di<RoutingManager>().selectCandidate(candidateId);
    await _syncRouteOverlay();
  }

  Future<void> _syncRouteOverlay() async {
    final controller = _controller;
    if (controller == null) return;
    final routingManager = di<RoutingManager>();
    await _routeOverlay.setRoutes(
      controller: controller,
      candidates: routingManager.candidates,
      selectedCandidate: routingManager.selectedCandidate,
    );
  }

  void _startNavigation() {
    di<RoutingManager>().startNavigation();
  }

  void _stopNavigation() {
    di<RoutingManager>().stopNavigation();
  }

  Future<void> _openTripPlanner() async {
    final target = di<MapSelectionManager>().selectedTarget;
    if (target == null) return;
    final start =
        await _currentStartLocation() ??
        _toGeoCoordinate(target.coordinates, target.name);
    await di<TripDraftManager>().ensureDraft(startLocation: start);
    if (!mounted) return;
    setState(() {
      _isTripComposerOpen = true;
    });
  }

  void _closeTripPlanner() {
    if (di<TripDraftManager>().pendingLocationPick != null) {
      unawaited(_cancelTripLocationPick());
    }
    setState(() {
      _isTripComposerOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectionManager = watchIt<MapSelectionManager>();
    final locationManager = watchIt<LocationManager>();
    final routingManager = watchIt<RoutingManager>();
    final agentManager = watchIt<TripAgentManager>();
    final tripDraftManager = watchIt<TripDraftManager>();
    final pendingPick = tripDraftManager.pendingLocationPick;
    final isPickingTripLocation = pendingPick != null;
    final isRouting = watch(
      routingManager.requestRoutesCommand.isRunning,
    ).value;
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= 720;
    final mobileSheetInitialSize = isPickingTripLocation
        ? 0.22
        : _isTripComposerOpen
        ? 0.86
        : 0.26;
    final mobileSheetMinSize = isPickingTripLocation
        ? 0.18
        : _isTripComposerOpen
        ? 0.55
        : 0.18;
    final mobileSheetMaxSize = isPickingTripLocation
        ? 0.32
        : _isTripComposerOpen
        ? 0.96
        : 0.5;
    final mobileSheetSnapSizes = isPickingTripLocation
        ? const [0.22, 0.32]
        : _isTripComposerOpen
        ? const [0.55, 0.86, 0.96]
        : const [0.26, 0.5];
    final topOrnamentInset = media.padding.top + _topMapOrnamentMargin;
    final bottomControlInset = isWide
        ? media.padding.bottom + _mapControlMargin
        : media.size.height * mobileSheetInitialSize + _mapControlMargin;
    _queueDraftLocationOverlaySync(pendingPick);

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
            myLocationEnabled: locationManager.isUserLocationEnabled,
            myLocationTrackingMode: locationManager.isUserLocationEnabled
                ? MyLocationTrackingMode.tracking
                : MyLocationTrackingMode.none,
            myLocationRenderMode: locationManager.isUserLocationEnabled
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
                    isRequesting: locationManager.isRequesting,
                    isLocationEnabled: locationManager.isUserLocationEnabled,
                    isPermanentlyDenied: locationManager.isPermanentlyDenied,
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
              width: _isTripComposerOpen ? 430 : 360,
              child: _isTripComposerOpen
                  ? TripComposerPanel(
                      selectedTarget: selectionManager.selectedTarget,
                      onClose: _closeTripPlanner,
                    )
                  : TargetDetailsPanel(
                      selectedTarget: selectionManager.selectedTarget,
                      isQuerying: selectionManager.isQuerying,
                      message:
                          selectionManager.message ?? locationManager.message,
                      routeCandidates: routingManager.candidates,
                      selectedRoute: routingManager.selectedCandidate,
                      isRouting: isRouting,
                      isNavigationActive: routingManager.isNavigationActive,
                      onNavigate: _navigateToSelectedTarget,
                      onTrip: _openTripPlanner,
                      onSelectRoute: _selectRoute,
                      onStartNavigation: _startNavigation,
                      onStopNavigation: _stopNavigation,
                    ),
            )
          else
            Positioned.fill(
              child: SafeArea(
                top: false,
                child: DraggableScrollableSheet(
                  key: ValueKey(
                    'map-sheet-$_isTripComposerOpen-$isPickingTripLocation',
                  ),
                  minChildSize: mobileSheetMinSize,
                  initialChildSize: mobileSheetInitialSize,
                  maxChildSize: mobileSheetMaxSize,
                  snap: true,
                  snapSizes: mobileSheetSnapSizes,
                  builder: (context, scrollController) => _isTripComposerOpen
                      ? isPickingTripLocation
                            ? _TripLocationPickPanel(
                                pending: pendingPick,
                                compact: true,
                                onCancel: () =>
                                    unawaited(_cancelTripLocationPick()),
                                onConfirmArea: () =>
                                    unawaited(_confirmTripAreaPick()),
                                onRadiusChanged: _updateTripAreaRadius,
                              )
                            : TripComposerPanel(
                                selectedTarget: selectionManager.selectedTarget,
                                onClose: _closeTripPlanner,
                                compact: true,
                                scrollController: scrollController,
                              )
                      : TargetDetailsPanel(
                          selectedTarget: selectionManager.selectedTarget,
                          isQuerying: selectionManager.isQuerying,
                          message:
                              selectionManager.message ??
                              locationManager.message,
                          routeCandidates: routingManager.candidates,
                          selectedRoute: routingManager.selectedCandidate,
                          isRouting: isRouting,
                          isNavigationActive: routingManager.isNavigationActive,
                          onNavigate: _navigateToSelectedTarget,
                          onTrip: _openTripPlanner,
                          onSelectRoute: _selectRoute,
                          onStartNavigation: _startNavigation,
                          onStopNavigation: _stopNavigation,
                          compact: true,
                          scrollController: scrollController,
                        ),
                ),
              ),
            ),
          if (isWide && pendingPick != null)
            Positioned(
              left: 12,
              right: _isTripComposerOpen ? 454 : 384,
              bottom: 12,
              child: _TripLocationPickPanel(
                pending: pendingPick,
                onCancel: () => unawaited(_cancelTripLocationPick()),
                onConfirmArea: () => unawaited(_confirmTripAreaPick()),
                onRadiusChanged: _updateTripAreaRadius,
              ),
            ),
          if (agentManager.isPlanning)
            const Positioned.fill(child: TripPlanningOverlay()),
        ],
      ),
    );
  }
}

GeoCoordinate _toGeoCoordinate(LatLng location, [String? label]) {
  return GeoCoordinate(
    lat: location.latitude,
    lon: location.longitude,
    label: label,
  );
}

GeoCoordinate _targetToGeoCoordinate(SelectedMapTarget target) {
  return GeoCoordinate(
    lat: target.coordinates.latitude,
    lon: target.coordinates.longitude,
    label: target.name,
  );
}

LatLng? _toLatLng(GeoCoordinate? coordinate) {
  if (coordinate == null) return null;
  return LatLng(coordinate.lat, coordinate.lon);
}

IconData _transportIcon(TransportMode mode) {
  return switch (mode) {
    TransportMode.walk => Icons.directions_walk,
    TransportMode.bike => Icons.directions_bike,
    TransportMode.drive => Icons.directions_car,
    TransportMode.publicTransport => Icons.directions_transit,
  };
}

class _TripLocationPickPanel extends StatelessWidget {
  const _TripLocationPickPanel({
    required this.pending,
    required this.onCancel,
    required this.onConfirmArea,
    required this.onRadiusChanged,
    this.compact = false,
  });

  final PendingTripLocationPick pending;
  final VoidCallback onCancel;
  final VoidCallback onConfirmArea;
  final ValueChanged<double> onRadiusChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArea = pending.kind.usesArea;
    final hasAreaCenter = pending.areaCenter != null;

    return SafeArea(
      top: false,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surface,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, compact ? 8 : 12, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isArea ? Icons.radio_button_unchecked : Icons.place,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isArea ? 'Select area' : 'Select location',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(onPressed: onCancel, child: const Text('Cancel')),
                  if (isArea)
                    FilledButton(
                      onPressed: hasAreaCenter ? onConfirmArea : null,
                      child: const Text('Confirm'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                isArea
                    ? hasAreaCenter
                          ? 'Adjust the radius or tap the map to move it.'
                          : 'Tap the map to place the area center.'
                    : 'Tap the map to place this activity.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (isArea) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.radar, size: 18),
                    Expanded(
                      child: Slider(
                        value: pending.radiusMeters
                            .clamp(100.0, 3000.0)
                            .toDouble(),
                        min: 100,
                        max: 3000,
                        divisions: 29,
                        label: _radiusLabel(pending.radiusMeters),
                        onChanged: onRadiusChanged,
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text(
                        _radiusLabel(pending.radiusMeters),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _radiusLabel(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
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
