import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';

/// One day's entries, read from a `logs/food/YYYY-MM.json` file.
class DailyFoodLog {
  DailyFoodLog({required DateTime date, List<FoodEntry> entries = const []})
    : date = dateOnly(date),
      entries = List.unmodifiable(
        List<FoodEntry>.of(entries)
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
      );

  factory DailyFoodLog.empty(DateTime date) => DailyFoodLog(date: date);

  factory DailyFoodLog.fromJson(
    Map<String, dynamic> json, {
    required DateTime date,
  }) {
    final rawEntries = json['entries'];
    final entries = <FoodEntry>[];

    if (rawEntries is List) {
      for (final rawEntry in rawEntries) {
        if (rawEntry is! Map) continue;
        try {
          entries.add(FoodEntry.fromJson(Map<String, dynamic>.from(rawEntry)));
        } on FormatException {
          // Skip only the malformed entry so one bad record cannot hide the
          // rest of the day's data.
        }
      }
    }

    return DailyFoodLog(date: date, entries: entries);
  }

  /// Local midnight for this log.
  final DateTime date;

  /// Entries sorted newest first.
  final List<FoodEntry> entries;

  int get totalCalories =>
      entries.fold(0, (total, entry) => total + entry.calories);

  int junkCalories(Set<String> junkCategories) => entries
      .where((entry) => junkCategories.contains(entry.category))
      .fold(0, (total, entry) => total + entry.calories);

  Map<String, dynamic> toJson() {
    return {
      'date': dateKey(date),
      'entries': entries.map((entry) => entry.toJson()).toList(),
    };
  }
}
