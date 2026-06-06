import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:iconify_flutter/icons/maki.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:permission_handler/permission_handler.dart';

const _appTitle = 'Questmap';
const _mapStyleAsset = 'assets/omt_style.json';
const _tileUserAgent = 'dev.questmap.questmap_app';
const _selectionSourceId = 'questmap-selection';
const _selectionLayerId = 'questmap-selection-circle';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    await setHttpHeaders({'User-Agent': _tileUserAgent});
  }

  runApp(const QuestmapApp());
}

class QuestmapApp extends StatelessWidget {
  const QuestmapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6F73)),
      ),
      home: const MapShell(),
    );
  }
}

class MapShell extends StatefulWidget {
  const MapShell({super.key});

  @override
  State<MapShell> createState() => _MapShellState();
}

class _MapShellState extends State<MapShell> {
  static const _initialCameraPosition = CameraPosition(
    target: LatLng(37.7749, -122.4194),
    zoom: 16,
  );

  static const _interactiveLayerIds = <String>[
    'poi-icons-priority',
    'poi-dots-known-dense',
    'poi-dots-other',
    'mountain-peak-points',
    'aerodrome-points',
    'water-name-points',
    'transportation-name-points',
    'poi-labels',
    'housenumber-labels',
    'place-labels',
    'transportation-labels',
  ];

  static const _styleIcons = <String, String>{
    'omt-aerialway': Maki.aerialway_15,
    'omt-airport': Maki.airport_15,
    'omt-alcohol-shop': Maki.alcohol_shop_15,
    'omt-art-gallery': Maki.art_gallery_15,
    'omt-attraction': Maki.attraction_15,
    'omt-bank': Maki.bank_15,
    'omt-bar': Maki.bar_15,
    'omt-beer': Maki.beer_15,
    'omt-bicycle': Maki.bicycle_15,
    'omt-bus': Maki.bus_15,
    'omt-cafe': Maki.cafe_15,
    'omt-campsite': Maki.campsite_15,
    'omt-car': Maki.car_15,
    'omt-castle': Maki.castle_15,
    'omt-cemetery': Maki.cemetery_15,
    'omt-circle': Maki.circle_15,
    'omt-college': Maki.college_15,
    'omt-dog-park': Maki.dog_park_15,
    'omt-drinking-water': Maki.drinking_water_15,
    'omt-entrance': Maki.entrance_15,
    'omt-fast-food': Maki.fast_food_15,
    'omt-fitness': Maki.fitness_centre_15,
    'omt-fuel': Maki.fuel_15,
    'omt-golf': Maki.golf_15,
    'omt-grocery': Maki.grocery_15,
    'omt-harbor': Maki.harbor_15,
    'omt-home': Maki.home_15,
    'omt-hospital': Maki.hospital_15,
    'omt-laundry': Maki.laundry_15,
    'omt-library': Maki.library_15,
    'omt-lodging': Maki.lodging_15,
    'omt-marker': Maki.marker_15,
    'omt-mountain': Maki.mountain_15,
    'omt-music': Maki.music_15,
    'omt-office': Maki.commercial_15,
    'omt-park': Maki.park_15,
    'omt-parking': Maki.parking_15,
    'omt-picnic-site': Maki.picnic_site_15,
    'omt-pitch': Maki.pitch_15,
    'omt-playground': Maki.playground_15,
    'omt-post': Maki.post_15,
    'omt-rail': Maki.rail_15,
    'omt-recycling': Maki.recycling_15,
    'omt-restaurant': Maki.restaurant_15,
    'omt-school': Maki.school_15,
    'omt-shelter': Maki.shelter_15,
    'omt-shop': Maki.shop_15,
    'omt-stadium': Maki.stadium_15,
    'omt-swimming': Maki.swimming_15,
    'omt-toilet': Maki.toilet_15,
    'omt-town-hall': Maki.town_hall_15,
    'omt-village': Maki.village_15,
    'omt-waste-basket': Maki.waste_basket_15,
    'omt-water': Maki.water_15,
  };

  MapLibreMapController? _controller;
  Symbol? _waypointSymbol;
  _SelectedMapTarget? _selectedTarget;
  LatLng? _lastUserLocation;
  PermissionStatus? _locationPermissionStatus;
  bool _selectionLayerReady = false;
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

    for (final entry in _styleIcons.entries) {
      final imageBytes = await _svgToPng(entry.value);
      await controller.addImage(entry.key, imageBytes, true);
    }

    await _addSelectionLayer(controller);
    final selectedTarget = _selectedTarget;
    if (selectedTarget != null) {
      await _setSelectionCircle(selectedTarget.coordinates, controller);
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
      _interactiveLayerIds,
      null,
    );

    if (!mounted) return;

    final renderedFeatures = features
        .whereType<Map>()
        .map(_RenderedFeatureInfo.fromFeature)
        .toList();
    final nearestFeature = await _nearestFeature(
      point,
      renderedFeatures,
      controller,
    );
    final selectedTarget = nearestFeature == null
        ? _SelectedMapTarget.waypoint(coordinates: coordinates)
        : _SelectedMapTarget.feature(
            feature: nearestFeature,
            fallbackCoordinates: coordinates,
          );

    if (nearestFeature == null) {
      await _setWaypointMarker(coordinates, controller);
    } else {
      await _setWaypointMarker(null, controller);
    }
    await _setSelectionCircle(selectedTarget.coordinates, controller);

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

  Future<void> _addSelectionLayer(MapLibreMapController controller) async {
    _selectionLayerReady = false;
    await controller.addGeoJsonSource(
      _selectionSourceId,
      _selectionFeatureCollection(),
    );
    await controller.addCircleLayer(
      _selectionSourceId,
      _selectionLayerId,
      const CircleLayerProperties(
        circleRadius: 12,
        circleColor: '#0066ff',
        circleOpacity: 0.28,
        circleStrokeColor: '#0066ff',
        circleStrokeWidth: 2,
        circleStrokeOpacity: 0.85,
      ),
      belowLayerId: 'poi-dots-other',
      enableInteraction: false,
    );
    _selectionLayerReady = true;
  }

  Future<void> _setSelectionCircle(
    LatLng? coordinates,
    MapLibreMapController controller,
  ) async {
    if (!_selectionLayerReady) return;

    await controller.setGeoJsonSource(
      _selectionSourceId,
      _selectionFeatureCollection(coordinates),
    );
  }

  static Map<String, dynamic> _selectionFeatureCollection([
    LatLng? coordinates,
  ]) {
    return {
      'type': 'FeatureCollection',
      'features': [
        if (coordinates != null)
          {
            'type': 'Feature',
            'properties': <String, Object?>{},
            'geometry': {
              'type': 'Point',
              'coordinates': [coordinates.longitude, coordinates.latitude],
            },
          },
      ],
    };
  }

  Future<void> _setWaypointMarker(
    LatLng? coordinates,
    MapLibreMapController controller,
  ) async {
    final existingSymbol = _waypointSymbol;
    if (coordinates == null) {
      if (existingSymbol != null) {
        await controller.removeSymbol(existingSymbol);
        _waypointSymbol = null;
      }
      return;
    }

    final options = SymbolOptions(
      geometry: coordinates,
      iconImage: 'omt-marker',
      iconSize: 1.8,
      iconColor: '#0066ff',
      iconHaloColor: '#ffffff',
      iconHaloWidth: 1.5,
    );

    if (existingSymbol == null) {
      _waypointSymbol = await controller.addSymbol(options);
    } else {
      await controller.updateSymbol(existingSymbol, options);
    }
  }

  Future<_RenderedFeatureInfo?> _nearestFeature(
    math.Point<double> tapPoint,
    List<_RenderedFeatureInfo> features,
    MapLibreMapController controller,
  ) async {
    if (features.isEmpty) return null;

    final featureDistances = <_FeatureDistance>[];
    for (final feature in features) {
      final screenPoint = await _screenPointForFeature(feature, controller);
      featureDistances.add(
        _FeatureDistance(
          feature,
          screenPoint == null
              ? double.infinity
              : _distance(tapPoint, screenPoint),
        ),
      );
    }

    featureDistances.sort((a, b) {
      final distanceCompare = a.distance.compareTo(b.distance);
      if (distanceCompare != 0) return distanceCompare;
      return _interactiveLayerPriority(
        a.feature.layerId,
      ).compareTo(_interactiveLayerPriority(b.feature.layerId));
    });

    return featureDistances.first.feature;
  }

  Future<math.Point<double>?> _screenPointForFeature(
    _RenderedFeatureInfo feature,
    MapLibreMapController controller,
  ) async {
    final coordinates = feature.coordinates;
    if (coordinates == null) return null;

    final point = await controller.toScreenLocation(coordinates);
    return math.Point(point.x.toDouble(), point.y.toDouble());
  }

  static int _interactiveLayerPriority(String layerId) {
    final index = _interactiveLayerIds.indexOf(layerId);
    return index == -1 ? _interactiveLayerIds.length : index;
  }

  static double _distance(math.Point<double> a, math.Point<double> b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= 720;

    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            styleString: _mapStyleAsset,
            initialCameraPosition: _initialCameraPosition,
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            onMapClick: _onMapClick,
            onUserLocationUpdated: _onUserLocationUpdated,
            compassEnabled: true,
            compassViewPosition: CompassViewPosition.topRight,
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
            attributionButtonMargins: const math.Point(12, 12),
          ),
          const _MapTitleBadge(),
          Positioned(
            top: 64,
            left: 12,
            child: SafeArea(
              child: _LocationButton(
                isRequesting: _isRequestingLocation,
                isLocationEnabled: _isUserLocationEnabled,
                isPermanentlyDenied:
                    _locationPermissionStatus?.isPermanentlyDenied ?? false,
                onRequest: _requestUserLocationPermission,
                onRecenter: _goToUserLocation,
                onOpenSettings: _openLocationSettings,
              ),
            ),
          ),
          if (isWide)
            Positioned(
              top: 12,
              right: 12,
              bottom: 12,
              width: 360,
              child: _FeatureDetailsPanel(
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
                  builder: (context, scrollController) => _FeatureDetailsPanel(
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

  Future<Uint8List> _svgToPng(String svg, {int size = 48}) async {
    final pictureInfo = await vg.loadPicture(
      SvgStringLoader(svg.replaceAll('currentColor', '#000000')),
      null,
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final sourceSize = pictureInfo.size;
    final scale =
        size /
        math.max(
          sourceSize.width == 0 ? size.toDouble() : sourceSize.width,
          sourceSize.height == 0 ? size.toDouble() : sourceSize.height,
        );
    final dx = (size - sourceSize.width * scale) / 2;
    final dy = (size - sourceSize.height * scale) / 2;

    canvas
      ..translate(dx, dy)
      ..scale(scale);
    canvas.drawPicture(pictureInfo.picture);

    final rasterPicture = recorder.endRecording();
    final image = await rasterPicture.toImage(size, size);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    pictureInfo.picture.dispose();
    rasterPicture.dispose();
    image.dispose();

    if (byteData == null) {
      throw StateError('Unable to rasterize Iconify SVG for MapLibre.');
    }

    return byteData.buffer.asUint8List();
  }
}

class _MapTitleBadge extends StatelessWidget {
  const _MapTitleBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Positioned(
      top: 12,
      left: 12,
      child: SafeArea(
        child: Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              _appTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationButton extends StatelessWidget {
  const _LocationButton({
    required this.isRequesting,
    required this.isLocationEnabled,
    required this.isPermanentlyDenied,
    required this.onRequest,
    required this.onRecenter,
    required this.onOpenSettings,
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
        heroTag: 'questmap-location',
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

class _FeatureDetailsPanel extends StatelessWidget {
  const _FeatureDetailsPanel({
    required this.selectedTarget,
    required this.isQuerying,
    required this.message,
    this.compact = false,
    this.scrollController,
  });

  final _SelectedMapTarget? selectedTarget;
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

  final _SelectedMapTarget? target;
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

  final _SelectedMapTarget? target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feature = target?.feature;
    final iconSvg = feature == null
        ? null
        : _MapShellState._styleIcons[feature.iconImage];

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

  final _SelectedMapTarget target;

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

class _SelectedMapTarget {
  const _SelectedMapTarget._({
    required this.coordinates,
    required this.isWaypoint,
    this.feature,
  });

  factory _SelectedMapTarget.feature({
    required _RenderedFeatureInfo feature,
    required LatLng fallbackCoordinates,
  }) => _SelectedMapTarget._(
    coordinates: feature.coordinates ?? fallbackCoordinates,
    feature: feature,
    isWaypoint: false,
  );

  factory _SelectedMapTarget.waypoint({required LatLng coordinates}) =>
      _SelectedMapTarget._(coordinates: coordinates, isWaypoint: true);

  final LatLng coordinates;
  final _RenderedFeatureInfo? feature;
  final bool isWaypoint;

  String get name => feature?.title ?? 'Waypoint';

  String get subtitle {
    final feature = this.feature;
    if (feature == null) return coordinateLabel;
    return feature.typeSummary;
  }

  String get coordinateLabel =>
      'Lat ${coordinates.latitude.toStringAsFixed(6)}, '
      'Lon ${coordinates.longitude.toStringAsFixed(6)}';
}

class _FeatureDistance {
  const _FeatureDistance(this.feature, this.distance);

  final _RenderedFeatureInfo feature;
  final double distance;
}

class _RenderedFeatureInfo {
  const _RenderedFeatureInfo({
    required this.layerId,
    required this.sourceLayer,
    required this.properties,
    required this.coordinates,
  });

  factory _RenderedFeatureInfo.fromFeature(Map<Object?, Object?> feature) {
    final layer = feature['layer'];
    final properties = feature['properties'];

    final normalizedProperties = _propertyMap(properties);
    final inferredSourceLayer = _inferSourceLayer(normalizedProperties);

    return _RenderedFeatureInfo(
      layerId: _stringValue(_mapValue(layer)?['id']) ?? 'rendered point',
      sourceLayer:
          _stringValue(
            _mapValue(layer)?['source-layer'] ??
                _mapValue(layer)?['sourceLayer'],
          ) ??
          inferredSourceLayer,
      properties: normalizedProperties,
      coordinates: _pointCoordinates(feature['geometry']),
    );
  }

  final String layerId;
  final String sourceLayer;
  final Map<String, String> properties;
  final LatLng? coordinates;

  String get layerSummary => '$sourceLayer / $layerId';

  String get typeSummary {
    final displayType = _displayType;
    final values = <String>[
      ?displayType,
      if (sourceLayer.isNotEmpty) sourceLayer,
      if (layerId.isNotEmpty) layerId,
    ];
    return values.join(' / ');
  }

  String get title {
    for (final key in const ['name', 'name_en', 'housenumber']) {
      final value = properties[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return _displayType ?? sourceLayer;
  }

  String get iconImage {
    final subclass = properties['subclass'];
    final objectClass = properties['class'];
    return switch (subclass) {
      'playground' => 'omt-playground',
      'recycling' => 'omt-recycling',
      'waste_basket' => 'omt-waste-basket',
      'post_box' => 'omt-post',
      'bicycle_parking' => 'omt-bicycle',
      'parking' => 'omt-parking',
      'toilets' => 'omt-toilet',
      'drinking_water' => 'omt-drinking-water',
      'shelter' => 'omt-shelter',
      'picnic_site' || 'picnic_table' => 'omt-picnic-site',
      'camp_site' || 'campsite' => 'omt-campsite',
      'dog_park' => 'omt-dog-park',
      'fitness_station' || 'fitness_centre' => 'omt-fitness',
      'bollard' => 'omt-circle',
      _ => switch (objectClass) {
        'shop' => 'omt-shop',
        'office' => 'omt-office',
        'town_hall' => 'omt-town-hall',
        'fast_food' => 'omt-fast-food',
        'bus' => 'omt-bus',
        'railway' => 'omt-rail',
        'aerialway' => 'omt-aerialway',
        'laundry' => 'omt-laundry',
        'grocery' => 'omt-grocery',
        'library' => 'omt-library',
        'college' => 'omt-college',
        'lodging' => 'omt-lodging',
        'ice_cream' || 'cafe' => 'omt-cafe',
        'post' => 'omt-post',
        'school' => 'omt-school',
        'alcohol_shop' => 'omt-alcohol-shop',
        'bar' => 'omt-bar',
        'harbor' => 'omt-harbor',
        'car' => 'omt-car',
        'hospital' => 'omt-hospital',
        'cemetery' => 'omt-cemetery',
        'attraction' => 'omt-attraction',
        'beer' => 'omt-beer',
        'music' => 'omt-music',
        'stadium' => 'omt-stadium',
        'art_gallery' => 'omt-art-gallery',
        'clothing_store' => 'omt-shop',
        'swimming' => 'omt-swimming',
        'castle' => 'omt-castle',
        'atm' => 'omt-bank',
        'fuel' => 'omt-fuel',
        'bollard' => 'omt-circle',
        _ => 'omt-circle',
      },
    };
  }

  String? get _displayType {
    final value = properties['subclass'] ?? properties['class'];
    if (value == null || value.isEmpty) return null;
    return value
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static Map<Object?, Object?>? _mapValue(Object? value) {
    if (value is Map<Object?, Object?>) return value;
    if (value is Map) return Map<Object?, Object?>.from(value);
    return null;
  }

  static String? _stringValue(Object? value) {
    if (value == null) return null;
    final string = value.toString();
    return string.isEmpty ? null : string;
  }

  static Map<String, String> _propertyMap(Object? value) {
    final raw = _mapValue(value);
    if (raw == null) return {};

    final entries = <MapEntry<String, String>>[];
    for (final entry in raw.entries) {
      final key = _stringValue(entry.key);
      final entryValue = _stringValue(entry.value);
      if (key == null || entryValue == null) continue;
      if (key.startsWith('name:') && key != 'name:en') continue;
      entries.add(MapEntry(key, entryValue));
    }

    entries.sort((a, b) => a.key.compareTo(b.key));
    return Map<String, String>.fromEntries(entries.take(24));
  }

  static LatLng? _pointCoordinates(Object? value) {
    final geometry = _mapValue(value);
    if (geometry == null) return null;
    if (_stringValue(geometry['type']) != 'Point') return null;

    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.length < 2) return null;

    final longitude = _doubleValue(coordinates[0]);
    final latitude = _doubleValue(coordinates[1]);
    if (latitude == null || longitude == null) return null;

    return LatLng(latitude, longitude);
  }

  static double? _doubleValue(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String _inferSourceLayer(Map<String, String> properties) {
    if (properties.containsKey('housenumber')) return 'housenumber';
    if (properties.containsKey('iata') || properties.containsKey('icao')) {
      return 'aerodrome_label';
    }
    if (properties.containsKey('ele') || properties.containsKey('ele_ft')) {
      return 'mountain_peak';
    }
    if (properties.containsKey('class') && properties.containsKey('subclass')) {
      return 'poi';
    }
    if (properties.containsKey('class') && properties.containsKey('rank')) {
      return 'poi';
    }
    if (properties.containsKey('ref')) return 'transportation_name';
    if (properties.containsKey('name')) return 'place';
    return 'OpenMapTiles';
  }
}
