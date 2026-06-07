class TransitLegDetails {
  const TransitLegDetails({
    this.fromLabel,
    this.toLabel,
    this.routeName,
    this.routeShortName,
    this.routeLongName,
    this.displayName,
    this.vehicleType,
    this.headsign,
    this.agencyName,
    this.startTime,
    this.endTime,
    this.scheduledStartTime,
    this.scheduledEndTime,
    this.realTime,
    this.cancelled,
    this.intermediateStopLabels = const [],
    this.instructions = const [],
  });

  factory TransitLegDetails.fromJson(Map<String, Object?> json) {
    return TransitLegDetails(
      fromLabel: json['fromLabel'] as String?,
      toLabel: json['toLabel'] as String?,
      routeName: json['routeName'] as String?,
      routeShortName: json['routeShortName'] as String?,
      routeLongName: json['routeLongName'] as String?,
      displayName: json['displayName'] as String?,
      vehicleType: json['vehicleType'] as String?,
      headsign: json['headsign'] as String?,
      agencyName: json['agencyName'] as String?,
      startTime: _dateTime(json['startTime']),
      endTime: _dateTime(json['endTime']),
      scheduledStartTime: _dateTime(json['scheduledStartTime']),
      scheduledEndTime: _dateTime(json['scheduledEndTime']),
      realTime: json['realTime'] as bool?,
      cancelled: json['cancelled'] as bool?,
      intermediateStopLabels: _stringList(json['intermediateStopLabels']),
      instructions: _stringList(json['instructions']),
    );
  }

  final String? fromLabel;
  final String? toLabel;
  final String? routeName;
  final String? routeShortName;
  final String? routeLongName;
  final String? displayName;
  final String? vehicleType;
  final String? headsign;
  final String? agencyName;
  final DateTime? startTime;
  final DateTime? endTime;
  final DateTime? scheduledStartTime;
  final DateTime? scheduledEndTime;
  final bool? realTime;
  final bool? cancelled;
  final List<String> intermediateStopLabels;
  final List<String> instructions;

  String? get vehicleLabel =>
      displayName ?? routeShortName ?? routeName ?? routeLongName;

  bool get hasTiming =>
      startTime != null ||
      endTime != null ||
      scheduledStartTime != null ||
      scheduledEndTime != null;

  Map<String, Object?> toJson() => {
    if (fromLabel != null) 'fromLabel': fromLabel,
    if (toLabel != null) 'toLabel': toLabel,
    if (routeName != null) 'routeName': routeName,
    if (routeShortName != null) 'routeShortName': routeShortName,
    if (routeLongName != null) 'routeLongName': routeLongName,
    if (displayName != null) 'displayName': displayName,
    if (vehicleType != null) 'vehicleType': vehicleType,
    if (headsign != null) 'headsign': headsign,
    if (agencyName != null) 'agencyName': agencyName,
    if (startTime != null) 'startTime': startTime!.toIso8601String(),
    if (endTime != null) 'endTime': endTime!.toIso8601String(),
    if (scheduledStartTime != null)
      'scheduledStartTime': scheduledStartTime!.toIso8601String(),
    if (scheduledEndTime != null)
      'scheduledEndTime': scheduledEndTime!.toIso8601String(),
    if (realTime != null) 'realTime': realTime,
    if (cancelled != null) 'cancelled': cancelled,
    if (intermediateStopLabels.isNotEmpty)
      'intermediateStopLabels': intermediateStopLabels,
    if (instructions.isNotEmpty) 'instructions': instructions,
  };
}

DateTime? _dateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  throw const FormatException('Expected date-time string.');
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList();
}
