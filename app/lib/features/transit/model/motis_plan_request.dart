enum MotisMode {
  walk('WALK'),
  bike('BIKE'),
  rental('RENTAL'),
  car('CAR'),
  carParking('CAR_PARKING'),
  carDropoff('CAR_DROPOFF'),
  odm('ODM'),
  rideSharing('RIDE_SHARING'),
  flex('FLEX'),
  debugBusRoute('DEBUG_BUS_ROUTE'),
  debugRailwayRoute('DEBUG_RAILWAY_ROUTE'),
  debugFerryRoute('DEBUG_FERRY_ROUTE'),
  transit('TRANSIT'),
  tram('TRAM'),
  subway('SUBWAY'),
  ferry('FERRY'),
  airplane('AIRPLANE'),
  bus('BUS'),
  coach('COACH'),
  rail('RAIL'),
  highspeedRail('HIGHSPEED_RAIL'),
  longDistance('LONG_DISTANCE'),
  nightRail('NIGHT_RAIL'),
  regionalFastRail('REGIONAL_FAST_RAIL'),
  regionalRail('REGIONAL_RAIL'),
  suburban('SUBURBAN'),
  funicular('FUNICULAR'),
  aerialLift('AERIAL_LIFT'),
  other('OTHER'),
  arealLift('AREAL_LIFT'),
  metro('METRO'),
  cableCar('CABLE_CAR');

  const MotisMode(this.value);

  final String value;
}

enum MotisPedestrianProfile {
  foot('FOOT'),
  wheelchair('WHEELCHAIR');

  const MotisPedestrianProfile(this.value);

  final String value;
}

enum MotisElevationCosts {
  none('NONE'),
  low('LOW'),
  high('HIGH');

  const MotisElevationCosts(this.value);

  final String value;
}

enum MotisAlgorithm {
  raptor('RAPTOR'),
  pong('PONG'),
  tb('TB');

  const MotisAlgorithm(this.value);

  final String value;
}

class MotisPlanRequest {
  const MotisPlanRequest({
    required this.fromPlace,
    required this.toPlace,
    this.radius,
    this.via,
    this.viaMinimumStay,
    this.time,
    this.maxTransfers,
    this.maxTravelTime,
    this.minTransferTime,
    this.additionalTransferTime,
    this.transferTimeFactor,
    this.maxMatchingDistance,
    this.pedestrianProfile,
    this.pedestrianSpeed,
    this.cyclingSpeed,
    this.elevationCosts,
    this.useRoutedTransfers,
    this.detailedTransfers,
    this.detailedLegs,
    this.joinInterlinedLegs,
    this.transitModes,
    this.directModes,
    this.preTransitModes,
    this.postTransitModes,
    this.numItineraries,
    this.maxItineraries,
    this.pageCursor,
    this.timetableView,
    this.arriveBy,
    this.searchWindow,
    this.requireBikeTransport,
    this.requireCarTransport,
    this.maxPreTransitTime,
    this.maxPostTransitTime,
    this.maxDirectTime,
    this.fastestDirectFactor,
    this.timeout,
    this.passengers,
    this.luggage,
    this.slowDirect,
    this.fastestSlowDirectFactor,
    this.withFares,
    this.numLegAlternatives,
    this.withScheduledSkippedStops,
    this.language,
    this.algorithm,
  });

  final String fromPlace;
  final String toPlace;
  final double? radius;
  final List<String>? via;
  final List<int>? viaMinimumStay;
  final DateTime? time;
  final int? maxTransfers;
  final int? maxTravelTime;
  final int? minTransferTime;
  final int? additionalTransferTime;
  final double? transferTimeFactor;
  final double? maxMatchingDistance;
  final MotisPedestrianProfile? pedestrianProfile;
  final double? pedestrianSpeed;
  final double? cyclingSpeed;
  final MotisElevationCosts? elevationCosts;
  final bool? useRoutedTransfers;
  final bool? detailedTransfers;
  final bool? detailedLegs;
  final bool? joinInterlinedLegs;
  final List<MotisMode>? transitModes;
  final List<MotisMode>? directModes;
  final List<MotisMode>? preTransitModes;
  final List<MotisMode>? postTransitModes;
  final int? numItineraries;
  final int? maxItineraries;
  final String? pageCursor;
  final bool? timetableView;
  final bool? arriveBy;
  final int? searchWindow;
  final bool? requireBikeTransport;
  final bool? requireCarTransport;
  final int? maxPreTransitTime;
  final int? maxPostTransitTime;
  final int? maxDirectTime;
  final double? fastestDirectFactor;
  final int? timeout;
  final int? passengers;
  final int? luggage;
  final bool? slowDirect;
  final double? fastestSlowDirectFactor;
  final bool? withFares;
  final int? numLegAlternatives;
  final bool? withScheduledSkippedStops;
  final List<String>? language;
  final MotisAlgorithm? algorithm;

  Map<String, Object?> toQueryParameters() => {
    'fromPlace': fromPlace,
    'toPlace': toPlace,
    if (radius != null) 'radius': radius,
    if (via != null) 'via': _join(via!),
    if (viaMinimumStay != null) 'viaMinimumStay': _join(viaMinimumStay!),
    if (time != null) 'time': time!.toIso8601String(),
    if (maxTransfers != null) 'maxTransfers': maxTransfers,
    if (maxTravelTime != null) 'maxTravelTime': maxTravelTime,
    if (minTransferTime != null) 'minTransferTime': minTransferTime,
    if (additionalTransferTime != null)
      'additionalTransferTime': additionalTransferTime,
    if (transferTimeFactor != null) 'transferTimeFactor': transferTimeFactor,
    if (maxMatchingDistance != null) 'maxMatchingDistance': maxMatchingDistance,
    if (pedestrianProfile != null)
      'pedestrianProfile': pedestrianProfile!.value,
    if (pedestrianSpeed != null) 'pedestrianSpeed': pedestrianSpeed,
    if (cyclingSpeed != null) 'cyclingSpeed': cyclingSpeed,
    if (elevationCosts != null) 'elevationCosts': elevationCosts!.value,
    if (useRoutedTransfers != null) 'useRoutedTransfers': useRoutedTransfers,
    if (detailedTransfers != null) 'detailedTransfers': detailedTransfers,
    if (detailedLegs != null) 'detailedLegs': detailedLegs,
    if (joinInterlinedLegs != null) 'joinInterlinedLegs': joinInterlinedLegs,
    if (transitModes != null) 'transitModes': _joinModes(transitModes!),
    if (directModes != null) 'directModes': _joinModes(directModes!),
    if (preTransitModes != null)
      'preTransitModes': _joinModes(preTransitModes!),
    if (postTransitModes != null)
      'postTransitModes': _joinModes(postTransitModes!),
    if (numItineraries != null) 'numItineraries': numItineraries,
    if (maxItineraries != null) 'maxItineraries': maxItineraries,
    if (pageCursor != null) 'pageCursor': pageCursor,
    if (timetableView != null) 'timetableView': timetableView,
    if (arriveBy != null) 'arriveBy': arriveBy,
    if (searchWindow != null) 'searchWindow': searchWindow,
    if (requireBikeTransport != null)
      'requireBikeTransport': requireBikeTransport,
    if (requireCarTransport != null) 'requireCarTransport': requireCarTransport,
    if (maxPreTransitTime != null) 'maxPreTransitTime': maxPreTransitTime,
    if (maxPostTransitTime != null) 'maxPostTransitTime': maxPostTransitTime,
    if (maxDirectTime != null) 'maxDirectTime': maxDirectTime,
    if (fastestDirectFactor != null) 'fastestDirectFactor': fastestDirectFactor,
    if (timeout != null) 'timeout': timeout,
    if (passengers != null) 'passengers': passengers,
    if (luggage != null) 'luggage': luggage,
    if (slowDirect != null) 'slowDirect': slowDirect,
    if (fastestSlowDirectFactor != null)
      'fastestSlowDirectFactor': fastestSlowDirectFactor,
    if (withFares != null) 'withFares': withFares,
    if (numLegAlternatives != null) 'numLegAlternatives': numLegAlternatives,
    if (withScheduledSkippedStops != null)
      'withScheduledSkippedStops': withScheduledSkippedStops,
    if (language != null) 'language': _join(language!),
    if (algorithm != null) 'algorithm': algorithm!.value,
  };

  static String _join(Iterable<Object> values) => values.join(',');

  static String _joinModes(Iterable<MotisMode> modes) =>
      modes.map((mode) => mode.value).join(',');
}
