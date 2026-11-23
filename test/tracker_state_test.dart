import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:junk_food_tracker/core/services/vault_service.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/features/food/models/daily_food_log.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_vault_service.dart';

void main() {
  late Directory tempDirectory;
  late TrackerState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'junk_food_tracker_state_',
    );
    state = TrackerState();
    await state.setVaultPath(tempDirectory.path);
  });

  tearDown(() async {
    state.dispose();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('loads config into memory on open', () async {
    expect(state.status, VaultStatus.ready);
    expect(state.vaultPath, tempDirectory.path);
    expect(state.config.dailyCalorieGoal, 2200);
    expect(state.foodCategories, contains('Healthy'));
  });

  test('config updates are immediate and flushed to disk', () async {
    await state.setDailyCalorieGoal(1900);

    // In-memory value is available before the file check.
    expect(state.config.dailyCalorieGoal, 1900);

    final reader = VaultService();
    await reader.initialize(tempDirectory.path);
    final onDisk = await reader.loadConfig();
    expect(onDisk.dailyCalorieGoal, 1900);
  });

  test('adding an entry updates today and writes the daily file', () async {
    final now = DateTime.now();
    final entry = FoodEntry(
      id: 'entry-1',
      foodName: 'Double Cheeseburger',
      calories: 650,
      category: 'Junk',
      timestamp: now,
    );

    await state.addFoodEntry(entry);

    expect(state.todayEntries, hasLength(1));
    expect(state.todayTotalCalories, 650);
    expect(state.todayJunkCalories, 650);

    final reader = VaultService();
    await reader.initialize(tempDirectory.path);
    final log = await reader.loadDailyLog(now);
    expect(log.entries.single.foodName, 'Double Cheeseburger');

    await state.deleteFoodEntry(entry);
    expect(state.todayEntries, isEmpty);
    expect(state.todayTotalCalories, 0);
  });

  test('first launch without a saved path needs setup', () async {
    SharedPreferences.setMockInitialValues({});
    final freshState = TrackerState();
    await freshState.init();

    expect(freshState.status, VaultStatus.needsVaultSetup);
    expect(freshState.vaultPath, isNull);
    freshState.dispose();
  });

  test('category and junk settings persist through config.json', () async {
    expect(await state.addFoodCategory(' Desserts '), isTrue);
    expect(state.foodCategories, contains('Desserts'));
    expect(await state.addFoodCategory('desserts'), isFalse);

    await state.setCategoryCountsAsJunk('Desserts', true);
    expect(state.junkFoodCategories, contains('Desserts'));

    final reader = VaultService();
    await reader.initialize(tempDirectory.path);
    var savedConfig = await reader.loadConfig();
    expect(savedConfig.foodCategories, contains('Desserts'));
    expect(savedConfig.junkFoodCategories, contains('Desserts'));

    expect(await state.removeFoodCategory('Desserts'), isTrue);
    expect(state.foodCategories, isNot(contains('Desserts')));
    expect(state.junkFoodCategories, isNot(contains('Desserts')));

    savedConfig = await reader.loadConfig();
    expect(savedConfig.foodCategories, isNot(contains('Desserts')));
  });

  test('at least one food category is kept', () async {
    while (state.foodCategories.length > 1) {
      expect(
        await state.removeFoodCategory(state.foodCategories.first),
        isTrue,
      );
    }

    final lastCategory = state.foodCategories.single;
    expect(await state.removeFoodCategory(lastCategory), isFalse);
    expect(state.foodCategories, [lastCategory]);
  });

  test('presets can be added, updated by id, and deleted', () async {
    const first = FoodPreset(
      id: 'preset-a',
      name: 'Apple',
      calories: 95,
      defaultCategory: 'Healthy',
    );
    const second = FoodPreset(
      id: 'preset-b',
      name: 'Pizza',
      calories: 600,
      defaultCategory: 'Junk',
    );

    await state.upsertPreset(first);
    await state.upsertPreset(second);
    expect(state.presets, hasLength(2));

    await state.upsertPreset(first.copyWith(calories: 110));
    expect(state.presets, hasLength(2));
    expect(
      state.presets.firstWhere((preset) => preset.id == 'preset-a').calories,
      110,
    );

    await state.deletePreset('preset-b');
    expect(state.presets.map((preset) => preset.id), ['preset-a']);

    final reader = VaultService();
    await reader.initialize(tempDirectory.path);
    final saved = await reader.loadPresets();
    expect(saved.single.id, 'preset-a');
    expect(saved.single.calories, 110);
  });

  test('editing an entry moves it between daily logs', () async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1, 10);
    final today = DateTime(now.year, now.month, now.day, 12);
    final original = FoodEntry(
      id: 'move-me',
      foodName: 'Late snack',
      calories: 250,
      category: 'Snacks',
      timestamp: yesterday,
    );

    await state.addFoodEntry(original);
    expect(state.entriesForDate(yesterday).single.id, 'move-me');

    await state.updateFoodEntry(
      original.copyWith(timestamp: today, calories: 300),
      previousTimestamp: yesterday,
    );

    expect(state.entriesForDate(yesterday), isEmpty);
    expect(state.todayEntries.single.id, 'move-me');
    expect(state.todayTotalCalories, 300);

    final reader = VaultService();
    await reader.initialize(tempDirectory.path);
    expect((await reader.loadDailyLog(yesterday)).entries, isEmpty);
    expect((await reader.loadDailyLog(today)).entries.single.calories, 300);
  });

  test('loads historical days on demand and aggregates ranges', () async {
    final now = DateTime.now();
    final oldDate = DateTime(now.year, now.month, now.day - 40, 12);
    final oldEntry = FoodEntry(
      id: 'old-entry',
      foodName: 'Old Meal',
      calories: 500,
      category: 'Junk',
      timestamp: oldDate,
    );

    final writer = VaultService();
    await writer.initialize(tempDirectory.path);
    await writer.writeDailyLog(
      DailyFoodLog(date: oldDate, entries: [oldEntry]),
    );

    expect(state.entriesForDate(oldDate), isEmpty);

    await state.ensureLogsLoaded(oldDate, oldDate);
    expect(state.entriesForDate(oldDate).single.foodName, 'Old Meal');
    expect(state.entriesInRange(oldDate, oldDate), hasLength(1));
    expect(state.todayTotalCalories, 0);
  });

  test('recent entries cover seven days, newest first', () async {
    final now = DateTime.now();

    Future<void> add(String name, DateTime at) {
      return state.addFoodEntry(
        FoodEntry(
          id: name,
          foodName: name,
          calories: 100,
          category: 'Snacks',
          timestamp: at,
        ),
      );
    }

    await add('Eight days ago', DateTime(now.year, now.month, now.day - 8, 10));
    await add('Yesterday', DateTime(now.year, now.month, now.day - 1, 10));
    await add('Morning', DateTime(now.year, now.month, now.day, 8));
    await add('Noon', DateTime(now.year, now.month, now.day, 12));

    expect(state.recentEntries.map((entry) => entry.foodName), [
      'Noon',
      'Morning',
      'Yesterday',
    ]);
  });

  test('saved vault path is restored on the next launch', () async {
    final restored = TrackerState();
    await restored.init();

    expect(restored.status, VaultStatus.ready);
    expect(restored.vaultPath, tempDirectory.path);
    restored.dispose();
  });

  test('invalid vault path reports an error', () async {
    final file = File('${tempDirectory.path}/not-a-directory');
    await file.writeAsString('x');

    final broken = TrackerState();
    await broken.setVaultPath(file.path);

    expect(broken.status, VaultStatus.error);
    expect(broken.errorMessage, contains('Could not open the vault'));
    broken.dispose();
  });

  test('write failures keep memory values and surface an error', () async {
    final fake = FakeVaultService();
    final fakeState = TrackerState(vaultService: fake);
    await fakeState.setVaultPath('/virtual/write-failure');

    fake.failWrites = true;
    await fakeState.setDailyCalorieGoal(1900);
    expect(fakeState.config.dailyCalorieGoal, 1900);
    expect(fakeState.lastWriteError, contains('Simulated vault write failure'));

    fake.failWrites = false;
    await fakeState.setDailyCalorieGoal(2000);
    expect(fakeState.lastWriteError, isNull);

    fake.failWrites = true;
    await fakeState.setDailyCalorieGoal(2100);
    expect(fakeState.lastWriteError, isNotNull);
    fakeState.clearLastWriteError();
    expect(fakeState.lastWriteError, isNull);

    fakeState.dispose();
  });

  test('adding the same entry id replaces it instead of duplicating', () async {
    final now = DateTime.now();
    final entry = FoodEntry(
      id: 'duplicate-id',
      foodName: 'First name',
      calories: 200,
      category: 'Snacks',
      timestamp: now,
    );

    await state.addFoodEntry(entry);
    await state.addFoodEntry(
      entry.copyWith(foodName: 'Second name', calories: 350),
    );

    expect(state.todayEntries, hasLength(1));
    expect(state.todayEntries.single.foodName, 'Second name');
    expect(state.todayTotalCalories, 350);
  });

  test('deleting an unknown entry is a no-op', () async {
    final now = DateTime.now();
    final entry = FoodEntry(
      id: 'missing',
      foodName: 'Not saved',
      calories: 100,
      category: 'Snacks',
      timestamp: now,
    );

    await state.deleteFoodEntry(entry);

    expect(state.todayEntries, isEmpty);
    expect(state.lastWriteError, isNull);
  });

  test('invalid goal changes are ignored', () async {
    await state.setDailyCalorieGoal(0);
    expect(state.config.dailyCalorieGoal, 2200);

    await state.setDailyCalorieGoal(-100);
    expect(state.config.dailyCalorieGoal, 2200);

    await state.setDailyCalorieGoal(2200);
    expect(state.config.dailyCalorieGoal, 2200);
  });

  test('range loading caches days and notifies once per call', () async {
    final fake = FakeVaultService();
    final rangeState = TrackerState(vaultService: fake);
    await rangeState.setVaultPath('/virtual/range-vault');

    final first = DateTime(2026, 1, 2, 9);
    final second = DateTime(2026, 1, 4, 18);
    fake.logs[dateKey(first)] = DailyFoodLog(
      date: first,
      entries: [
        FoodEntry(
          id: 'range-1',
          foodName: 'Toast',
          calories: 120,
          category: 'Healthy',
          timestamp: first,
        ),
      ],
    );
    fake.logs[dateKey(second)] = DailyFoodLog(
      date: second,
      entries: [
        FoodEntry(
          id: 'range-2',
          foodName: 'Pizza',
          calories: 600,
          category: 'Junk',
          timestamp: second,
        ),
      ],
    );

    var notifications = 0;
    rangeState.addListener(() => notifications++);

    expect(rangeState.entriesInRange(first, second), isEmpty);

    await rangeState.ensureLogsLoaded(first, second);
    expect(notifications, 1);
    expect(
      rangeState.entriesInRange(first, second).map((entry) => entry.foodName),
      containsAll(<String>['Toast', 'Pizza']),
    );

    // The second call is served entirely from cache but still refreshes
    // listeners so screens can rebuild after an awaited load.
    await rangeState.ensureLogsLoaded(first, second);
    expect(notifications, 2);
    expect(rangeState.entriesInRange(first, second), hasLength(2));

    rangeState.dispose();
  });

  test('junk categories can be toggled both ways', () async {
    expect(state.isJunkCategory('Snacks'), isFalse);

    await state.setCategoryCountsAsJunk('Snacks', true);
    expect(state.junkFoodCategories, contains('Snacks'));
    expect(state.isJunkCategory('Snacks'), isTrue);

    await state.setCategoryCountsAsJunk('Snacks', false);
    expect(state.junkFoodCategories, isNot(contains('Snacks')));
    expect(state.isJunkCategory('Snacks'), isFalse);
  });
}
