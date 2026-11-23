import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';

/// In-memory representation of one `logs/food/YYYY-MM.json` file.
///
/// A monthly file holds every entry for the month. Callers use
/// [entriesForDate] to get the day-scoped view used by the dashboard.
class MonthlyFoodLog {
  MonthlyFoodLog({required DateTime month, List<FoodEntry> entries = const []})
    : month = monthOnly(month),
      entries = List.unmodifiable(
        List<FoodEntry>.of(entries)
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
      );

  factory MonthlyFoodLog.empty(DateTime month) => MonthlyFoodLog(month: month);

  factory MonthlyFoodLog.fromJson(
    Map<String, dynamic> json, {
    required DateTime month,
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
          // rest of the month's data.
        }
      }
    }

    return MonthlyFoodLog(month: month, entries: entries);
  }

  /// Local first day of the month this file belongs to.
  final DateTime month;

  /// Every entry in the month, sorted newest first.
  final List<FoodEntry> entries;

  /// Entries whose local timestamp falls on [date].
  List<FoodEntry> entriesForDate(DateTime date) => List.unmodifiable(
    entries.where((entry) => isSameDate(entry.timestamp, date)),
  );

  /// Replaces only [date]'s entries while keeping the rest of the month.
  MonthlyFoodLog withEntriesForDate(
    DateTime date,
    List<FoodEntry> dateEntries,
  ) {
    final remaining = entries.where(
      (entry) => !isSameDate(entry.timestamp, date),
    );
    return MonthlyFoodLog(
      month: month,
      entries: [...remaining, ...dateEntries],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'month': monthKey(month),
      'entries': entries.map((entry) => entry.toJson()).toList(),
    };
  }
}
