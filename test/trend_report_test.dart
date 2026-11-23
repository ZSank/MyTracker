import 'package:flutter_test/flutter_test.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';
import 'package:junk_food_tracker/features/trends/models/trend_report.dart';

void main() {
  final now = DateTime(2026, 11, 23, 12);

  FoodEntry entry({
    required String id,
    required int calories,
    required String category,
    required DateTime at,
  }) {
    return FoodEntry(
      id: id,
      foodName: 'Food $id',
      calories: calories,
      category: category,
      timestamp: at,
    );
  }

  final entries = [
    entry(
      id: '1',
      calories: 300,
      category: 'Healthy',
      at: DateTime(2026, 11, 16, 8),
    ),
    entry(
      id: '2',
      calories: 500,
      category: 'Junk',
      at: DateTime(2026, 11, 16, 12, 30),
    ),
    entry(
      id: '3',
      calories: 200,
      category: 'Healthy',
      at: DateTime(2026, 11, 18, 9, 15),
    ),
    entry(
      id: '4',
      calories: 100,
      category: 'Junk',
      at: DateTime(2026, 11, 18, 18, 45),
    ),
    entry(
      id: '5',
      calories: 400,
      category: 'Protein',
      at: DateTime(2026, 11, 22, 10),
    ),
    entry(
      id: '6',
      calories: 700,
      category: 'Junk',
      at: DateTime(2026, 11, 25, 10),
    ),
  ];

  bool isJunk(String category) => category == 'Junk';

  test('week report runs Monday to Sunday and ignores other weeks', () {
    final period = TrendPeriod.containing(
      TrendRange.week,
      DateTime(2026, 11, 18),
    );
    final report = TrendReport.fromEntries(
      period: period,
      entries: entries,
      isJunkCategory: isJunk,
      now: now,
    );

    expect(period.start, DateTime(2026, 11, 16));
    expect(period.end, DateTime(2026, 11, 22));
    expect(period.start.weekday, DateTime.monday);
    expect(report.buckets, hasLength(7));
    expect(report.totalCalories, 1500);
    expect(report.totalJunkCalories, 600);
    expect(report.entryCount, 5);
    expect(report.loggedDayCount, 3);
    expect(report.elapsedDayCount, 7);
    expect(report.dailyAverageCalories, 214);
    expect(report.junkPercentage, 40);

    expect(report.dailyBuckets[0].totalCalories, 800);
    expect(report.dailyBuckets[0].junkCalories, 500);
    expect(report.dailyBuckets[2].totalCalories, 300);
    expect(report.dailyBuckets[2].junkCalories, 100);
    expect(report.dailyBuckets[6].totalCalories, 400);
    expect(report.dailyBuckets[1].totalCalories, 0);

    expect(report.peakDay?.date, DateTime(2026, 11, 16));
    expect(report.peakDay?.totalCalories, 800);
  });

  test('day report buckets entries by hour', () {
    final period = TrendPeriod.containing(
      TrendRange.day,
      DateTime(2026, 11, 18),
    );
    final report = TrendReport.fromEntries(
      period: period,
      entries: entries,
      isJunkCategory: isJunk,
      now: now,
    );

    expect(report.buckets, hasLength(24));
    expect(report.totalCalories, 300);
    expect(report.totalJunkCalories, 100);
    expect(report.entryCount, 2);
    expect(report.loggedDayCount, 1);
    expect(report.buckets[9].totalCalories, 200);
    expect(report.buckets[9].junkCalories, 0);
    expect(report.buckets[18].totalCalories, 100);
    expect(report.buckets[18].junkCalories, 100);
    expect(report.buckets[8].totalCalories, 0);
    expect(report.peakBucket?.date.hour, 9);
    expect(report.peakBucket?.totalCalories, 200);
    expect(report.dailyAverageCalories, 300);
  });

  test('month report fills every day and averages elapsed days', () {
    final period = TrendPeriod.containing(
      TrendRange.month,
      DateTime(2026, 11, 18),
    );
    final report = TrendReport.fromEntries(
      period: period,
      entries: entries,
      isJunkCategory: isJunk,
      now: now,
    );

    expect(period.start, DateTime(2026, 11, 1));
    expect(period.end, DateTime(2026, 11, 30));
    expect(report.buckets, hasLength(30));
    expect(report.dailyBuckets, hasLength(30));
    expect(report.totalCalories, 2200);
    expect(report.totalJunkCalories, 1300);
    expect(report.entryCount, 6);
    expect(report.loggedDayCount, 4);
    expect(report.elapsedDayCount, 23);
    expect(report.dailyAverageCalories, 96);
    expect(report.junkPercentage, 59);

    expect(report.dailyBuckets[24].totalCalories, 700);
    expect(report.dailyBuckets[29].totalCalories, 0);
    expect(report.peakDay?.date, DateTime(2026, 11, 16));
    expect(report.peakDay?.totalCalories, 800);
  });

  test('periods shift by their calendar window', () {
    final month = TrendPeriod.containing(
      TrendRange.month,
      DateTime(2026, 1, 31),
    );
    final nextMonth = month.shift(1);
    expect(nextMonth.start, DateTime(2026, 2, 1));
    expect(nextMonth.end, DateTime(2026, 2, 28));

    final week = TrendPeriod.containing(
      TrendRange.week,
      DateTime(2026, 11, 18),
    );
    expect(week.shift(1).start, DateTime(2026, 11, 23));
    expect(week.shift(-1).start, DateTime(2026, 11, 9));

    final day = TrendPeriod.containing(TrendRange.day, DateTime(2026, 11, 18));
    expect(day.shift(1).start, DateTime(2026, 11, 19));
    expect(day.shift(1).end, DateTime(2026, 11, 19));
  });

  test('weeks and months cross year boundaries', () {
    final week = TrendPeriod.containing(TrendRange.week, DateTime(2026, 1, 1));
    expect(week.start, DateTime(2025, 12, 29));
    expect(week.end, DateTime(2026, 1, 4));
    expect(week.dayCount, 7);

    final december = TrendPeriod.containing(
      TrendRange.month,
      DateTime(2026, 12, 15),
    );
    expect(december.shift(1).start, DateTime(2027, 1, 1));
    expect(december.shift(1).end, DateTime(2027, 1, 31));

    final january = TrendPeriod.containing(
      TrendRange.month,
      DateTime(2026, 1, 15),
    );
    expect(january.shift(-1).start, DateTime(2025, 12, 1));
    expect(january.shift(-1).end, DateTime(2025, 12, 31));
  });

  test('future periods are empty and have a zero average', () {
    final period = TrendPeriod.containing(
      TrendRange.month,
      DateTime(2026, 12, 1),
    );
    final report = TrendReport.fromEntries(
      period: period,
      entries: entries,
      isJunkCategory: isJunk,
      now: now,
    );

    expect(report.entryCount, 0);
    expect(report.totalCalories, 0);
    expect(report.totalJunkCalories, 0);
    expect(report.elapsedDayCount, 0);
    expect(report.dailyAverageCalories, 0);
    expect(report.junkPercentage, 0);
    expect(report.peakBucket, isNull);
    expect(report.peakDay, isNull);
  });

  test('period windows exclude entries on the boundary days outside them', () {
    final day = TrendPeriod.containing(TrendRange.day, DateTime(2026, 11, 18));
    final report = TrendReport.fromEntries(
      period: day,
      entries: entries,
      isJunkCategory: isJunk,
      now: now,
    );

    expect(report.entryCount, 2);
    expect(report.dailyBuckets.single.date, DateTime(2026, 11, 18));
    expect(report.dailyBuckets.single.totalCalories, 300);
  });
}
