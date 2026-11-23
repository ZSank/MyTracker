import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/features/food/models/daily_food_log.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';
import 'package:junk_food_tracker/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_vault_service.dart';

void main() {
  const vaultPath = '/virtual/trends-vault';
  late FakeVaultService vault;
  late TrackerState trackerState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      TrackerState.vaultPathPreferenceKey: vaultPath,
    });
    vault = FakeVaultService();
    trackerState = TrackerState(vaultService: vault);
    await trackerState.init();
  });

  Future<void> seedToday() async {
    final now = DateTime.now();
    await trackerState.addFoodEntry(
      FoodEntry(
        id: 'trend-1',
        foodName: 'Oatmeal',
        calories: 300,
        category: 'Healthy',
        timestamp: DateTime(now.year, now.month, now.day, 8, 30),
      ),
    );
    await trackerState.addFoodEntry(
      FoodEntry(
        id: 'trend-2',
        foodName: 'Chocolate',
        calories: 200,
        category: 'Junk',
        timestamp: DateTime(now.year, now.month, now.day, 13, 45),
      ),
    );
  }

  Future<void> openTrends(WidgetTester tester) async {
    await tester.pumpWidget(JunkFoodTrackerApp(trackerState: trackerState));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-trends-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('trends screen charts week, day and month ranges', (
    tester,
  ) async {
    await seedToday();
    await openTrends(tester);

    expect(find.text('Trends & Analytics'), findsOneWidget);
    expect(find.text('Avg / day'), findsOneWidget);
    expect(find.text('Top day'), findsOneWidget);
    expect(find.byKey(const Key('trends-period-title')), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);

    final weekChart = tester.widget<BarChart>(find.byType(BarChart));
    expect(weekChart.data.barGroups, hasLength(7));
    final todayIndex = DateTime.now().weekday - DateTime.monday;
    expect(weekChart.data.barGroups[todayIndex].barRods.single.toY, 500);

    final nextWeek = tester.widget<IconButton>(
      find.byKey(const Key('trends-next-period')),
    );
    expect(nextWeek.onPressed, isNull);

    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();

    expect(find.text('Calories by hour'), findsOneWidget);
    expect(find.text('Day total'), findsOneWidget);
    expect(find.text('Peak hour'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
    final dayTitle = tester
        .widget<Text>(find.byKey(const Key('trends-period-title')))
        .data;
    expect(dayTitle, startsWith('Today'));

    final primaryMetric = find.byKey(const Key('trends-metric-primary'));
    final junkMetric = find.byKey(const Key('trends-metric-junk'));
    final peakMetric = find.byKey(const Key('trends-metric-peak'));

    expect(
      find.descendant(of: primaryMetric, matching: find.textContaining('500')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: primaryMetric, matching: find.text('2 entries')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: junkMetric, matching: find.textContaining('200')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: junkMetric, matching: find.text('40% of total')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: peakMetric, matching: find.textContaining('300')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: peakMetric, matching: find.text('at 8 AM')),
      findsOneWidget,
    );

    final dayChart = tester.widget<BarChart>(find.byType(BarChart));
    expect(dayChart.data.barGroups, hasLength(24));
    expect(dayChart.data.barGroups[8].barRods.single.toY, 300);
    expect(dayChart.data.barGroups[13].barRods.single.toY, 200);

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();

    expect(find.text('Calories by day'), findsOneWidget);
    expect(find.text('Avg / day'), findsOneWidget);
    expect(find.text('Top day'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);

    final currentMonth = tester
        .widget<Text>(find.byKey(const Key('trends-period-title')))
        .data;
    await tester.tap(find.byKey(const Key('trends-previous-period')));
    await tester.pumpAndSettle();

    final previousMonth = tester
        .widget<Text>(find.byKey(const Key('trends-period-title')))
        .data;
    expect(previousMonth, isNot(currentMonth));

    final canReturn = tester.widget<IconButton>(
      find.byKey(const Key('trends-next-period')),
    );
    expect(canReturn.onPressed, isNotNull);
  });

  testWidgets('trends screen shows an empty state without logs', (
    tester,
  ) async {
    await openTrends(tester);

    expect(find.text('No food logged in this period'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
  });

  testWidgets('previous month lazy-loads historical daily logs', (
    tester,
  ) async {
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1, 15, 12);
    final previousMonthDays = DateTime(
      previousMonth.year,
      previousMonth.month + 1,
      0,
    ).day;
    vault.logs[dateKey(previousMonth)] = DailyFoodLog(
      date: previousMonth,
      entries: [
        FoodEntry(
          id: 'historical-1',
          foodName: 'Pizza',
          calories: 900,
          category: 'Junk',
          timestamp: previousMonth,
        ),
      ],
    );

    await openTrends(tester);
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trends-previous-period')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('trends-period-title'))).data,
      DateFormat.yMMMM().format(previousMonth),
    );
    expect(find.text('1 entry across 1 day'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);

    final chart = tester.widget<BarChart>(find.byType(BarChart));
    expect(chart.data.barGroups, hasLength(previousMonthDays));

    final primaryMetric = find.byKey(const Key('trends-metric-primary'));
    final junkMetric = find.byKey(const Key('trends-metric-junk'));
    final peakMetric = find.byKey(const Key('trends-metric-peak'));

    expect(
      find.descendant(
        of: primaryMetric,
        matching: find.text('over $previousMonthDays days'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: junkMetric, matching: find.textContaining('900')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: peakMetric, matching: find.textContaining('900')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: peakMetric,
        matching: find.text(DateFormat('MMM d').format(previousMonth)),
      ),
      findsOneWidget,
    );

    final nextButton = tester.widget<IconButton>(
      find.byKey(const Key('trends-next-period')),
    );
    expect(nextButton.onPressed, isNotNull);
  });

  testWidgets('trends load failures show an error with retry', (tester) async {
    await openTrends(tester);
    expect(find.byType(BarChart), findsNothing);

    vault.failReads = true;
    await tester.tap(find.byKey(const Key('trends-previous-period')));
    await tester.pumpAndSettle();

    expect(find.text('Could not load logs'), findsOneWidget);
    expect(find.byKey(const Key('trends-retry-button')), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);

    vault.failReads = false;
    await tester.tap(find.byKey(const Key('trends-retry-button')));
    await tester.pumpAndSettle();

    expect(find.text('Could not load logs'), findsNothing);
    expect(find.text('No food logged in this period'), findsOneWidget);
  });
}
