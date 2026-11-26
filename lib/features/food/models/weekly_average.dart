/// Average intake across the logged days of the current Monday-start week.
class WeeklyAverage {
  const WeeklyAverage({
    required this.calories,
    required this.protein,
    required this.loggedDays,
  });

  /// Average calories per logged day.
  final int calories;

  /// Average protein per logged day, or null when no entry had protein.
  final num? protein;

  /// Number of days in the week that have at least one entry.
  final int loggedDays;

  bool get hasData => loggedDays > 0;
}
