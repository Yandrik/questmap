class TimeConstraint {
  const TimeConstraint({
    this.startTime,
    this.arrivalTime,
    required this.durationMinutes,
  }) : assert(durationMinutes > 0);

  factory TimeConstraint.fromJson(Map<String, Object?> json) {
    return TimeConstraint(
      startTime: _dateTime(json['startTime']),
      arrivalTime: _dateTime(json['arrivalTime']),
      durationMinutes: _requiredInt(json['durationMinutes'], 'durationMinutes'),
    );
  }

  final DateTime? startTime;
  final DateTime? arrivalTime;
  final int durationMinutes;

  Map<String, Object?> toJson() => {
    if (startTime != null) 'startTime': startTime!.toIso8601String(),
    if (arrivalTime != null) 'arrivalTime': arrivalTime!.toIso8601String(),
    'durationMinutes': durationMinutes,
  };

  TimeConstraint copyWith({
    DateTime? startTime,
    DateTime? arrivalTime,
    int? durationMinutes,
    bool clearStartTime = false,
    bool clearArrivalTime = false,
  }) {
    return TimeConstraint(
      startTime: clearStartTime ? null : startTime ?? this.startTime,
      arrivalTime: clearArrivalTime ? null : arrivalTime ?? this.arrivalTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }

  static DateTime? _dateTime(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    throw FormatException('Expected date-time string.');
  }

  static int _requiredInt(Object? value, String field) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw FormatException('Expected integer $field.');
  }
}
