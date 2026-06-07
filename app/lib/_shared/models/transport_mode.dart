enum TransportMode {
  walk('walk', 'Walk'),
  bike('bike', 'Bike'),
  drive('drive', 'Drive'),
  publicTransport('publicTransport', 'ÖPNV');

  const TransportMode(this.apiValue, this.displayLabel);

  final String apiValue;
  final String displayLabel;

  bool get usesValhalla => this != TransportMode.publicTransport;

  String? get valhallaCostingValue => switch (this) {
    TransportMode.walk => 'pedestrian',
    TransportMode.bike => 'bicycle',
    TransportMode.drive => 'auto',
    TransportMode.publicTransport => null,
  };

  String get iconKey => switch (this) {
    TransportMode.walk => 'walk',
    TransportMode.bike => 'bike',
    TransportMode.drive => 'drive',
    TransportMode.publicTransport => 'public_transport',
  };

  static TransportMode fromApiValue(String value) {
    return TransportMode.values.firstWhere(
      (mode) => mode.apiValue == value,
      orElse: () => throw FormatException('Unknown transport mode $value.'),
    );
  }
}
