import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';

/// The three aggregation windows offered by the Trends screen.
enum TrendRange { day, week, month }

/// An inclusive calendar window (local midnights) for a trend report.
class TrendPeriod {
  const TrendPeriod({
    required this.range,
    required this.start,
    required this.end,
  });

  /// Builds the period that contains [anchor].
  ///
  /// Weeks start on Monday. Months span the full calendar month.
  factory TrendPeriod.containing(TrendRange range, DateTime anchor) {
    final day = dateOnly(anchor);

    switch (range) {
      case TrendRange.day:
        return TrendPeriod(range: range, start: day, end: day);
      case TrendRange.week:
        final start = DateTime(
          day.year,
          day.month,
          day.day - (day.weekday - DateTime.monday),
        );
        return TrendPeriod(
          range: range,
          start: start,
          end: DateTime(start.year, start.month, start.day + 6),
        );
      case TrendRange.month:
        return TrendPeriod(
          range: range,
          start: DateTime(day.year, day.month),
          end: DateTime(day.year, day.month + 1, 0),
        );
    }
  }

  final TrendRange range;
  final DateTime start;
  final DateTime end;

  int get dayCount => _daysBetween(start, end) + 1;

  bool contains(DateTime value) {
    final day = dateOnly(value);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  /// Moves the window by one day, week or month, clamped to calendar bounds.
  TrendPeriod shift(int steps) {
    switch (range) {
      case TrendRange.day:
        return TrendPeriod.containing(
          range,
          DateTime(start.year, start.month, start.day + steps),
        );
      case TrendRange.week:
        return TrendPeriod.containing(
          range,
          DateTime(start.year, start.month, start.day + steps * 7),
        );
      case TrendRange.month:
        return TrendPeriod.containing(
          range,
          DateTime(start.year, start.month + steps),
        );
    }
  }
}

/// One bar in a trend chart: an hour for day view, a date for week/month.
class TrendBucket {
  const TrendBucket({
    required this.date,
    this.totalCalories = 0,
    this.junkCalories = 0,
    this.totalProtein,
    this.junkProtein,
  }) : assert(totalCalories >= 0),
       assert(junkCalories >= 0 && junkCalories <= totalCalories),
       assert(totalProtein == null || totalProtein >= 0),
       assert(junkProtein == null || junkProtein >= 0);

  final DateTime date;
  final int totalCalories;
  final int junkCalories;

  /// Protein in this bucket, or null when no entry had a protein value.
  final num? totalProtein;

  /// Protein contributed by junk-category entries, when known.
  final num? junkProtein;

  int get nonJunkCalories => totalCalories - junkCalories;
}

/// Aggregated calories for one [TrendPeriod].
///
/// This is a pure value object: all JSON/file access happens in
/// `TrackerState`, so the calculations are easy to test.
class TrendReport {
  const TrendReport({
    required this.period,
    required this.buckets,
    required this.dailyBuckets,
    required this.totalCalories,
    required this.totalJunkCalories,
    required this.entryCount,
    required this.loggedDayCount,
    required this.elapsedDayCount,
    required this.peakBucket,
    required this.peakDay,
    this.totalProtein,
    this.totalJunkProtein,
  });

  factory TrendReport.fromEntries({
    required TrendPeriod period,
    required Iterable<FoodEntry> entries,
    required bool Function(String category) isJunkCategory,
    DateTime? now,
  }) {
    final today = dateOnly(now ?? DateTime.now());
    final dailyTotals = <String, _BucketTotals>{};
    final hourlyTotals = List<_BucketTotals>.generate(
      24,
      (_) => _BucketTotals(),
    );
    var entryCount = 0;

    for (final entry in entries) {
      final timestamp = entry.timestamp.toLocal();
      final day = dateOnly(timestamp);
      if (day.isBefore(period.start) || day.isAfter(period.end)) continue;

      entryCount++;
      final isJunk = isJunkCategory(entry.category);
      final protein = entry.totalProtein;
      final key = dateKey(day);
      final dayTotals = dailyTotals[key] ??= _BucketTotals();
      dayTotals.add(entry.calories, protein, isJunk: isJunk);

      if (period.range == TrendRange.day) {
        hourlyTotals[timestamp.hour].add(
          entry.calories,
          protein,
          isJunk: isJunk,
        );
      }
    }

    final dailyBuckets = <TrendBucket>[];
    for (
      var day = period.start;
      !day.isAfter(period.end);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final totals = dailyTotals[dateKey(day)];
      dailyBuckets.add(
        totals == null
            ? TrendBucket(date: day)
            : TrendBucket(
                date: day,
                totalCalories: totals.total,
                junkCalories: totals.junk,
                totalProtein: totals.protein,
                junkProtein: totals.junkProtein,
              ),
      );
    }

    final buckets = period.range == TrendRange.day
        ? List<TrendBucket>.generate(24, (hour) {
            final totals = hourlyTotals[hour];
            return TrendBucket(
              date: DateTime(
                period.start.year,
                period.start.month,
                period.start.day,
                hour,
              ),
              totalCalories: totals.total,
              junkCalories: totals.junk,
              totalProtein: totals.protein,
              junkProtein: totals.junkProtein,
            );
          })
        : dailyBuckets;

    var totalCalories = 0;
    var totalJunkCalories = 0;
    num? totalProtein;
    num? totalJunkProtein;
    var loggedDayCount = 0;
    for (final bucket in dailyBuckets) {
      totalCalories += bucket.totalCalories;
      totalJunkCalories += bucket.junkCalories;
      final protein = bucket.totalProtein;
      if (protein != null) {
        totalProtein = (totalProtein ?? 0) + protein;
      }
      final junkProtein = bucket.junkProtein;
      if (junkProtein != null) {
        totalJunkProtein = (totalJunkProtein ?? 0) + junkProtein;
      }
      if (bucket.totalCalories > 0) loggedDayCount++;
    }

    final effectiveEnd = period.end.isAfter(today) ? today : period.end;
    final elapsedDayCount = period.start.isAfter(effectiveEnd)
        ? 0
        : _daysBetween(period.start, effectiveEnd) + 1;

    return TrendReport(
      period: period,
      buckets: List.unmodifiable(buckets),
      dailyBuckets: List.unmodifiable(dailyBuckets),
      totalCalories: totalCalories,
      totalJunkCalories: totalJunkCalories,
      totalProtein: totalProtein,
      totalJunkProtein: totalJunkProtein,
      entryCount: entryCount,
      loggedDayCount: loggedDayCount,
      elapsedDayCount: elapsedDayCount,
      peakBucket: _peak(buckets),
      peakDay: _peak(dailyBuckets),
    );
  }

  final TrendPeriod period;

  /// Chart buckets: hours in day view, days in week/month views.
  final List<TrendBucket> buckets;

  /// One bucket for every day in the period, including empty days.
  final List<TrendBucket> dailyBuckets;

  final int totalCalories;
  final int totalJunkCalories;

  /// Protein in the period, or null when no entry had a protein value.
  final num? totalProtein;

  /// Protein from junk-category entries, when known.
  final num? totalJunkProtein;

  final int entryCount;
  final int loggedDayCount;

  /// Days up to today (or the full period when it is in the past).
  final int elapsedDayCount;

  final TrendBucket? peakBucket;
  final TrendBucket? peakDay;

  int get dailyAverageCalories {
    if (elapsedDayCount == 0) return 0;
    return (totalCalories / elapsedDayCount).round();
  }

  /// Average protein per elapsed day, or null when no protein is known.
  num? get dailyAverageProtein {
    final protein = totalProtein;
    if (protein == null || elapsedDayCount == 0) return null;
    return protein / elapsedDayCount;
  }

  int get junkPercentage {
    if (totalCalories == 0) return 0;
    return ((totalJunkCalories / totalCalories) * 100).round();
  }

  static TrendBucket? _peak(Iterable<TrendBucket> buckets) {
    TrendBucket? peak;
    for (final bucket in buckets) {
      if (bucket.totalCalories <= 0) continue;
      if (peak == null || bucket.totalCalories > peak.totalCalories) {
        peak = bucket;
      }
    }
    return peak;
  }
}

class _BucketTotals {
  int total = 0;
  int junk = 0;
  num? protein;
  num? junkProtein;

  void add(int calories, num? proteinValue, {required bool isJunk}) {
    total += calories;
    if (proteinValue != null) {
      protein = (protein ?? 0) + proteinValue;
      if (isJunk) {
        junkProtein = (junkProtein ?? 0) + proteinValue;
      }
    }
    if (isJunk) junk += calories;
  }
}

int _daysBetween(DateTime start, DateTime end) {
  final first = DateTime.utc(start.year, start.month, start.day);
  final last = DateTime.utc(end.year, end.month, end.day);
  return last.difference(first).inDays;
}
