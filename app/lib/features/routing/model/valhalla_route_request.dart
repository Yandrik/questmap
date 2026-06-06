enum ValhallaCosting {
  auto('auto'),
  bicycle('bicycle'),
  pedestrian('pedestrian'),
  truck('truck'),
  bus('bus'),
  taxi('taxi'),
  motorScooter('motor_scooter'),
  motorcycle('motorcycle'),
  multimodal('multimodal'),
  bikeshare('bikeshare'),
  autoPedestrian('auto_pedestrian');

  const ValhallaCosting(this.value);

  final String value;
}

enum ValhallaShapeFormat {
  polyline6('polyline6'),
  polyline5('polyline5'),
  geojson('geojson'),
  noShape('no_shape');

  const ValhallaShapeFormat(this.value);

  final String value;
}

class ValhallaLocation {
  const ValhallaLocation({
    required this.lat,
    required this.lon,
    this.type = 'break',
    this.name,
  });

  final double lat;
  final double lon;
  final String type;
  final String? name;

  Map<String, Object?> toJson() => {
    'lat': lat,
    'lon': lon,
    'type': type,
    if (name != null) 'name': name,
  };
}

class ValhallaRouteRequest {
  const ValhallaRouteRequest({
    required this.locations,
    this.costing = ValhallaCosting.pedestrian,
    this.costingOptions,
    this.directionsOptions,
    this.shapeFormat = ValhallaShapeFormat.polyline6,
    this.units = 'kilometers',
    this.language,
  });

  final List<ValhallaLocation> locations;
  final ValhallaCosting costing;
  final Map<String, Object?>? costingOptions;
  final Map<String, Object?>? directionsOptions;
  final ValhallaShapeFormat shapeFormat;
  final String units;
  final String? language;

  Map<String, Object?> toJson() {
    if (locations.length < 2) {
      throw ArgumentError.value(
        locations,
        'locations',
        'Valhalla routes require at least two locations.',
      );
    }

    return {
      'locations': locations.map((location) => location.toJson()).toList(),
      'costing': costing.value,
      if (costingOptions != null) 'costing_options': costingOptions,
      if (directionsOptions != null) 'directions_options': directionsOptions,
      'shape_format': shapeFormat.value,
      'units': units,
      if (language != null) 'language': language,
    };
  }
}
