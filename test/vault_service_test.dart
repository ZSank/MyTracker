import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:junk_food_tracker/core/models/app_config.dart';
import 'package:junk_food_tracker/core/services/vault_service.dart';
import 'package:junk_food_tracker/features/food/models/daily_food_log.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDirectory;
  late VaultService vault;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'junk_food_tracker_vault_',
    );
    vault = VaultService();
    await vault.initialize(tempDirectory.path);
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('initialize creates the vault layout and default files', () async {
    expect(await vault.configFile.exists(), isTrue);
    expect(await vault.presetsFile.exists(), isTrue);
    expect(await vault.foodLogsDirectory.exists(), isTrue);

    final config = await vault.loadConfig();
    expect(config.vaultVersion, AppConfig.currentVaultVersion);
    expect(config.dailyCalorieGoal, 2200);
    expect(config.foodCategories, contains('Healthy'));
    expect(config.junkFoodCategories, contains('Junk'));
    expect(config.enabledModules, ['food']);

    expect(await vault.loadPresets(), isEmpty);
  });

  test('config round-trips through config.json', () async {
    final updated = AppConfig.defaults().copyWith(
      dailyCalorieGoal: 1850,
      foodCategories: ['Healthy', 'Treats'],
      junkFoodCategories: ['Treats'],
    );

    await vault.writeConfig(updated);
    final loaded = await vault.loadConfig();

    expect(loaded.dailyCalorieGoal, 1850);
    expect(loaded.foodCategories, ['Healthy', 'Treats']);
    expect(loaded.junkFoodCategories, ['Treats']);
    expect(loaded.enabledModules, ['food']);
  });

  test('presets round-trip through food_presets.json', () async {
    const preset = FoodPreset(
      id: 'preset-1',
      name: 'Oatmeal with Banana',
      calories: 320,
      defaultCategory: 'Healthy',
    );

    await vault.writePresets([preset]);
    final loaded = await vault.loadPresets();

    expect(loaded, hasLength(1));
    expect(loaded.single.id, preset.id);
    expect(loaded.single.name, preset.name);
    expect(loaded.single.calories, preset.calories);
    expect(loaded.single.defaultCategory, preset.defaultCategory);
  });

  test(
    'daily log writes to logs/food/YYYY-MM-DD.json and reads back',
    () async {
      final date = DateTime(2026, 11, 23, 8, 30);
      final entry = FoodEntry(
        id: 'entry-1',
        foodName: 'Oatmeal with Banana',
        calories: 320,
        category: 'Healthy',
        timestamp: date,
      );

      await vault.writeDailyLog(DailyFoodLog(date: date, entries: [entry]));

      final file = File(
        p.join(vault.foodLogsDirectory.path, '2026-11-23.json'),
      );
      expect(await file.exists(), isTrue);

      final loaded = await vault.loadDailyLog(date);
      expect(loaded.entries, hasLength(1));
      expect(loaded.entries.single.foodName, 'Oatmeal with Banana');
      expect(loaded.entries.single.calories, 320);
      expect(loaded.entries.single.timestamp, date);
      expect(loaded.totalCalories, 320);
    },
  );

  test('missing daily log starts empty and is not created on read', () async {
    final date = DateTime(2026, 11, 22);
    final log = await vault.loadDailyLog(date);

    expect(log.entries, isEmpty);
    expect(await vault.dailyLogFile(date).exists(), isFalse);
  });

  test('lists logged dates and merges ranges for trends', () async {
    final firstDate = DateTime(2026, 11, 21);
    final secondDate = DateTime(2026, 11, 22);

    await vault.writeDailyLog(
      DailyFoodLog(
        date: firstDate,
        entries: [
          FoodEntry(
            id: 'a',
            foodName: 'Apple',
            calories: 95,
            category: 'Healthy',
            timestamp: firstDate,
          ),
        ],
      ),
    );
    await vault.writeDailyLog(
      DailyFoodLog(
        date: secondDate,
        entries: [
          FoodEntry(
            id: 'b',
            foodName: 'Pizza',
            calories: 600,
            category: 'Junk',
            timestamp: secondDate,
          ),
        ],
      ),
    );

    final dates = await vault.listLoggedDates();
    expect(dates, [firstDate, secondDate]);

    final range = await vault.loadEntriesInRange(firstDate, secondDate);
    expect(range.map((entry) => entry.foodName), ['Pizza', 'Apple']);
  });

  test('malformed config is quarantined and replaced with defaults', () async {
    await vault.configFile.writeAsString('{not valid json');

    final config = await vault.loadConfig();
    expect(config.dailyCalorieGoal, 2200);

    final backups = tempDirectory.listSync().whereType<File>().where(
      (file) => file.path.contains('.corrupt-'),
    );
    expect(backups, isNotEmpty);
  });

  test('malformed presets are quarantined and reset', () async {
    await vault.presetsFile.writeAsString('{not valid json');

    expect(await vault.loadPresets(), isEmpty);

    final backups = tempDirectory.listSync().whereType<File>().where(
      (file) => file.path.contains('.corrupt-'),
    );
    expect(backups, isNotEmpty);
  });

  test('a malformed preset is skipped while valid presets survive', () async {
    await vault.presetsFile.writeAsString('''
[
  {"id":"good","name":"Apple","calories":95,"defaultCategory":"Healthy"},
  {"id":"bad","name":"Missing calories","defaultCategory":"Healthy"}
]
''');

    final presets = await vault.loadPresets();
    expect(presets, hasLength(1));
    expect(presets.single.id, 'good');
    expect(presets.single.name, 'Apple');
  });

  test('malformed daily logs are quarantined and read as empty', () async {
    final date = DateTime(2026, 11, 20);
    final file = vault.dailyLogFile(date);
    await file.writeAsString('{not valid json');

    final log = await vault.loadDailyLog(date);
    expect(log.entries, isEmpty);
    expect(await file.exists(), isFalse);

    final backups = vault.foodLogsDirectory.listSync().whereType<File>().where(
      (candidate) => candidate.path.contains('.corrupt-'),
    );
    expect(backups, isNotEmpty);
  });

  test('queued writes keep the last requested document', () async {
    final first = AppConfig.defaults().copyWith(dailyCalorieGoal: 1500);
    final second = AppConfig.defaults().copyWith(dailyCalorieGoal: 1700);

    final firstWrite = vault.writeConfig(first);
    final secondWrite = vault.writeConfig(second);
    await Future.wait([firstWrite, secondWrite]);

    expect((await vault.loadConfig()).dailyCalorieGoal, 1700);
  });

  test('a daily log keeps valid entries when one entry is malformed', () async {
    final date = DateTime(2026, 11, 19);
    final file = vault.dailyLogFile(date);
    await file.writeAsString('''
{
  "date": "2026-11-19",
  "entries": [
    {
      "id": "good",
      "foodName": "Apple",
      "calories": 95,
      "category": "Healthy",
      "timestamp": "2026-11-19T09:00:00.000Z"
    },
    {
      "id": "bad",
      "foodName": "Mystery",
      "category": "Healthy",
      "timestamp": "2026-11-19T10:00:00.000Z"
    }
  ]
}
''');

    final log = await vault.loadDailyLog(date);

    expect(log.entries, hasLength(1));
    expect(log.entries.single.id, 'good');
    expect(log.totalCalories, 95);
    expect(await file.exists(), isTrue);
  });

  test('reopening a vault never overwrites existing data', () async {
    final date = DateTime(2026, 11, 18);
    final entry = FoodEntry(
      id: 'keep-me',
      foodName: 'Soup',
      calories: 180,
      category: 'Healthy',
      timestamp: date,
    );

    await vault.writeConfig(
      AppConfig.defaults().copyWith(dailyCalorieGoal: 1750),
    );
    await vault.writeDailyLog(DailyFoodLog(date: date, entries: [entry]));

    final reopened = VaultService();
    await reopened.initialize(tempDirectory.path);

    expect((await reopened.loadConfig()).dailyCalorieGoal, 1750);
    final log = await reopened.loadDailyLog(date);
    expect(log.entries.single.id, 'keep-me');
    expect(log.entries.single.calories, 180);
  });

  test('logged date listing ignores non-log files', () async {
    final date = DateTime(2026, 11, 21);
    await vault.writeDailyLog(
      DailyFoodLog(
        date: date,
        entries: [
          FoodEntry(
            id: 'only-log',
            foodName: 'Toast',
            calories: 110,
            category: 'Healthy',
            timestamp: date,
          ),
        ],
      ),
    );
    await File(p.join(vault.foodLogsDirectory.path, 'notes.txt'))
        .writeAsString('not a log');
    await File(p.join(vault.foodLogsDirectory.path, '2026-11-22.json.tmp'))
        .writeAsString('{}');

    expect(await vault.listLoggedDates(), [date]);
  });
}
