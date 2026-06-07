enum TripPlannerMode {
  agent('agent', 'Agent'),
  deterministic('deterministic', 'Deterministic');

  const TripPlannerMode(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static TripPlannerMode fromApiValue(String value) {
    return TripPlannerMode.values.firstWhere(
      (mode) => mode.apiValue == value,
      orElse: () => throw FormatException('Unknown planner mode $value.'),
    );
  }
}
