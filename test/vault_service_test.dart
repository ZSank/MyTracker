import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:junk_food_tracker/core/models/app_config.dart';
import 'package:junk_food_tracker/core/services/vault_service.dart';
import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/features/food/models/daily_food_log.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDirectory;
  late VaultService vault;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
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

  test('daily logs share one file per month and read back', () async {
    final firstDate = DateTime(2026, 11, 23, 8, 30);
    final secondDate = DateTime(2026, 11, 24, 19);
    final firstEntry = FoodEntry(
      id: 'entry-1',
      foodName: 'Oatmeal with Banana',
      calories: 320,
      category: 'Healthy',
      timestamp: firstDate,
    );
    final secondEntry = FoodEntry(
      id: 'entry-2',
      foodName: 'Pizza',
      calories: 600,
      category: 'Junk',
      timestamp: secondDate,
    );

    await vault.writeDailyLog(
      DailyFoodLog(date: firstDate, entries: [firstEntry]),
    );
    await vault.writeDailyLog(
      DailyFoodLog(date: secondDate, entries: [secondEntry]),
    );

    final file = File(p.join(vault.foodLogsDirectory.path, '2026-11.json'));
    expect(await file.exists(), isTrue);
    expect(
      await vault.foodLogsDirectory
          .list()
          .where((entity) => entity is File)
          .length,
      1,
    );

    final loadedFirst = await vault.loadDailyLog(firstDate);
    expect(loadedFirst.entries, hasLength(1));
    expect(loadedFirst.entries.single.foodName, 'Oatmeal with Banana');
    expect(loadedFirst.entries.single.calories, 320);
    expect(loadedFirst.entries.single.timestamp, firstDate);
    expect(loadedFirst.totalCalories, 320);

    final loadedSecond = await vault.loadDailyLog(secondDate);
    expect(loadedSecond.entries.single.id, 'entry-2');

    // Replacing one day's entries must preserve the rest of the month.
    await vault.writeDailyLog(DailyFoodLog(date: firstDate, entries: const []));
    expect((await vault.loadDailyLog(firstDate)).entries, isEmpty);
    expect((await vault.loadDailyLog(secondDate)).entries.single.id, 'entry-2');
  });

  test('missing daily log starts empty and is not created on read', () async {
    final date = DateTime(2026, 11, 22);
    final log = await vault.loadDailyLog(date);

    expect(log.entries, isEmpty);
    expect(await vault.monthlyLogFile(date).exists(), isFalse);
  });

  test('lists logged dates and merges ranges for trends', () async {
    final firstDate = DateTime(2026, 11, 21);
    final secondDate = DateTime(2026, 11, 22);
    final thirdDate = DateTime(2026, 12, 2);

    Future<void> write(String id, String name, int calories, DateTime date) {
      return vault.writeDailyLog(
        DailyFoodLog(
          date: date,
          entries: [
            FoodEntry(
              id: id,
              foodName: name,
              calories: calories,
              category: 'Healthy',
              timestamp: date,
            ),
          ],
        ),
      );
    }

    await write('a', 'Apple', 95, firstDate);
    await write('b', 'Pizza', 600, secondDate);
    await write('c', 'Soup', 180, thirdDate);

    final dates = await vault.listLoggedDates();
    expect(dates, [firstDate, secondDate, thirdDate]);

    final range = await vault.loadEntriesInRange(firstDate, secondDate);
    expect(range.map((entry) => entry.foodName), ['Pizza', 'Apple']);

    final crossMonth = await vault.loadEntriesInRange(secondDate, thirdDate);
    expect(crossMonth.map((entry) => entry.foodName), ['Soup', 'Pizza']);

    expect(await vault.loadEntriesInRange(thirdDate, firstDate), isEmpty);
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

  test('malformed monthly logs are quarantined and read as empty', () async {
    final date = DateTime(2026, 11, 20);
    final file = vault.monthlyLogFile(date);
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

  test(
    'a monthly log keeps valid entries when one entry is malformed',
    () async {
      final date = DateTime(2026, 11, 19);
      final file = vault.monthlyLogFile(date);
      await file.writeAsString('''
{
  "month": "2026-11",
  "entries": [
    {
      "id": "good",
      "foodName": "Apple",
      "calories": 95,
      "category": "Healthy",
      "comment": "Afternoon snack",
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
      expect(log.entries.single.comment, 'Afternoon snack');
      expect(log.totalCalories, 95);
      expect(await file.exists(), isTrue);
    },
  );

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

  test('logged date listing ignores non-log files and empty days', () async {
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
    await vault.writeDailyLog(
      DailyFoodLog(date: DateTime(2026, 11, 20), entries: const []),
    );

    expect(await vault.listLoggedDates(), [date]);
  });

  test('legacy daily files migrate into one monthly file', () async {
    final firstDate = DateTime(2026, 11, 21, 9);
    final secondDate = DateTime(2026, 11, 22, 18);
    final firstFile = File(
      p.join(vault.foodLogsDirectory.path, '2026-11-21.json'),
    );
    final secondFile = File(
      p.join(vault.foodLogsDirectory.path, '2026-11-22.json'),
    );

    await firstFile.writeAsString(
      jsonEncode(
        DailyFoodLog(
          date: firstDate,
          entries: [
            FoodEntry(
              id: 'legacy-1',
              foodName: 'Apple',
              calories: 95,
              category: 'Healthy',
              timestamp: firstDate,
              comment: 'Old daily file',
            ),
          ],
        ).toJson(),
      ),
    );
    await secondFile.writeAsString(
      jsonEncode(
        DailyFoodLog(
          date: secondDate,
          entries: [
            FoodEntry(
              id: 'legacy-2',
              foodName: 'Rice',
              calories: 250,
              category: 'Healthy',
              timestamp: secondDate,
            ),
          ],
        ).toJson(),
      ),
    );

    final reopened = VaultService();
    await reopened.initialize(tempDirectory.path);

    expect(await firstFile.exists(), isFalse);
    expect(await secondFile.exists(), isFalse);
    expect(await reopened.monthlyLogFile(firstDate).exists(), isTrue);

    final firstLog = await reopened.loadDailyLog(firstDate);
    expect(firstLog.entries.single.id, 'legacy-1');
    expect(firstLog.entries.single.comment, 'Old daily file');
    expect(
      (await reopened.loadDailyLog(secondDate)).entries.single.id,
      'legacy-2',
    );
    expect(await reopened.listLoggedDates(), [
      dateOnly(firstDate),
      dateOnly(secondDate),
    ]);
    expect(
      await reopened.loadEntriesInRange(firstDate, secondDate),
      hasLength(2),
    );
  });

  test(
    'migration skips malformed legacy files without failing the vault',
    () async {
      final goodDate = DateTime(2026, 11, 20, 10);
      final goodFile = File(
        p.join(vault.foodLogsDirectory.path, '2026-11-20.json'),
      );
      final badFile = File(
        p.join(vault.foodLogsDirectory.path, '2026-11-19.json'),
      );

      await goodFile.writeAsString(
        jsonEncode(
          DailyFoodLog(
            date: goodDate,
            entries: [
              FoodEntry(
                id: 'good-legacy',
                foodName: 'Soup',
                calories: 180,
                category: 'Healthy',
                timestamp: goodDate,
              ),
            ],
          ).toJson(),
        ),
      );
      await badFile.writeAsString('{not valid json');

      final reopened = VaultService();
      await reopened.initialize(tempDirectory.path);

      expect(await goodFile.exists(), isFalse);
      expect(await badFile.exists(), isFalse);
      expect(
        (await reopened.loadDailyLog(goodDate)).entries.single.id,
        'good-legacy',
      );

      final backups = vault.foodLogsDirectory
          .listSync()
          .whereType<File>()
          .where((candidate) => candidate.path.contains('.corrupt-'));
      expect(backups, isNotEmpty);
    },
  );
}
