import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/features/workout/models/workout_entry.dart';

/// In-memory representation of one `logs/workouts/YYYY-MM.json` file.
class MonthlyWorkoutLog {
  MonthlyWorkoutLog({
    required DateTime month,
    List<WorkoutEntry> entries = const [],
  }) : month = monthOnly(month),
       entries = List.unmodifiable(
         List<WorkoutEntry>.of(entries)
           ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
       );

  factory MonthlyWorkoutLog.empty(DateTime month) =>
      MonthlyWorkoutLog(month: month);

  factory MonthlyWorkoutLog.fromJson(
    Map<String, dynamic> json, {
    required DateTime month,
  }) {
    final rawEntries = json['entries'];
    final entries = <WorkoutEntry>[];

    if (rawEntries is List) {
      for (final rawEntry in rawEntries) {
        if (rawEntry is! Map) continue;
        try {
          entries.add(
            WorkoutEntry.fromJson(Map<String, dynamic>.from(rawEntry)),
          );
        } on FormatException {
          // Skip only the malformed entry so one bad record cannot hide the
          // rest of the month's data.
        }
      }
    }

    return MonthlyWorkoutLog(month: month, entries: entries);
  }

  /// Local first day of the month this file belongs to.
  final DateTime month;

  /// Every workout in the month, sorted newest first.
  final List<WorkoutEntry> entries;

  /// Workouts whose local timestamp falls on [date].
  List<WorkoutEntry> entriesForDate(DateTime date) => List.unmodifiable(
    entries.where((entry) => isSameDate(entry.timestamp, date)),
  );

  Map<String, dynamic> toJson() {
    return {
      'month': monthKey(month),
      'entries': entries.map((entry) => entry.toJson()).toList(),
    };
  }
}
