import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:iconify_flutter/icons/maki.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

const _appTitle = 'Questmap';
const _mapStyleAsset = 'assets/omt_style.json';
const _tileUserAgent = 'dev.questmap.questmap_app';

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
  List<_RenderedFeatureInfo> _selectedFeatures = [];
  LatLng? _selectedCoordinates;
  bool _isQuerying = false;
  String? _message;

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
  }

  Future<void> _onMapClick(math.Point<double> point, LatLng coordinates) async {
    final controller = _controller;
    if (controller == null) return;

    setState(() {
      _isQuerying = true;
      _selectedCoordinates = coordinates;
      _message = null;
    });

    final features = await controller.queryRenderedFeaturesInRect(
      ui.Rect.fromLTRB(point.x - 8, point.y - 8, point.x + 8, point.y + 8),
      _interactiveLayerIds,
      null,
    );

    if (!mounted) return;

    final renderedFeatures =
        features.whereType<Map>().map(_RenderedFeatureInfo.fromFeature).toList()
          ..sort((a, b) => a.layerId.compareTo(b.layerId));

    setState(() {
      _isQuerying = false;
      _selectedFeatures = renderedFeatures;
      _message = renderedFeatures.isEmpty
          ? 'No rendered OpenMapTiles point object at this location.'
          : null;
    });
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
            compassEnabled: true,
            compassViewPosition: CompassViewPosition.topRight,
            logoEnabled: true,
            logoViewPosition: LogoViewPosition.bottomLeft,
            logoViewMargins: const math.Point(12, 12),
            trackCameraPosition: true,
            attributionButtonPosition: isWide
                ? AttributionButtonPosition.bottomLeft
                : AttributionButtonPosition.topLeft,
            attributionButtonMargins: const math.Point(12, 12),
          ),
          const _MapTitleBadge(),
          if (isWide)
            Positioned(
              top: 12,
              right: 12,
              bottom: 12,
              width: 360,
              child: _FeatureDetailsPanel(
                selectedCoordinates: _selectedCoordinates,
                selectedFeatures: _selectedFeatures,
                isQuerying: _isQuerying,
                message: _message,
              ),
            )
          else
            Positioned.fill(
              child: SafeArea(
                top: false,
                child: DraggableScrollableSheet(
                  minChildSize: 0.14,
                  initialChildSize: 0.22,
                  maxChildSize: 0.5,
                  snap: true,
                  snapSizes: const [0.22, 0.5],
                  builder: (context, scrollController) => _FeatureDetailsPanel(
                    selectedCoordinates: _selectedCoordinates,
                    selectedFeatures: _selectedFeatures,
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

class _FeatureDetailsPanel extends StatelessWidget {
  const _FeatureDetailsPanel({
    required this.selectedCoordinates,
    required this.selectedFeatures,
    required this.isQuerying,
    required this.message,
    this.compact = false,
    this.scrollController,
  });

  final LatLng? selectedCoordinates;
  final List<_RenderedFeatureInfo> selectedFeatures;
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
                Row(
                  children: [
                    Icon(
                      Icons.ads_click,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'OMT objects',
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
                ),
                const SizedBox(height: 8),
                Text(
                  _subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: selectedFeatures.isEmpty
                      ? _EmptyFeatureState(
                          message: message,
                          scrollController: scrollController,
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: selectedFeatures.length,
                          separatorBuilder: (_, _) => const Divider(height: 16),
                          itemBuilder: (context, index) =>
                              _FeatureTile(feature: selectedFeatures[index]),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _subtitle {
    final coordinates = selectedCoordinates;
    if (coordinates == null) {
      return 'Tap a visible point to inspect rendered OpenMapTiles features.';
    }

    return '${coordinates.latitude.toStringAsFixed(5)}, '
        '${coordinates.longitude.toStringAsFixed(5)}';
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

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.feature});

  final _RenderedFeatureInfo feature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          feature.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          feature.layerSummary,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        if (feature.properties.isEmpty)
          Text(
            'No properties in this rendered feature.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
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
    );
  }
}

class _RenderedFeatureInfo {
  const _RenderedFeatureInfo({
    required this.layerId,
    required this.sourceLayer,
    required this.properties,
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
    );
  }

  final String layerId;
  final String sourceLayer;
  final Map<String, String> properties;

  String get layerSummary => '$sourceLayer / $layerId';

  String get title {
    for (final key in const ['name', 'name_en', 'housenumber', 'class']) {
      final value = properties[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return sourceLayer;
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
