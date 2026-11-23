import 'package:flutter_test/flutter_test.dart';
import 'package:junk_food_tracker/core/models/app_config.dart';
import 'package:junk_food_tracker/features/food/models/daily_food_log.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';
import 'package:junk_food_tracker/features/food/models/monthly_food_log.dart';

void main() {
  group('AppConfig', () {
    test('defaults describe the food module, goal and junk categories', () {
      final config = AppConfig.defaults();

      expect(config.vaultVersion, AppConfig.currentVaultVersion);
      expect(config.dailyCalorieGoal, 2200);
      expect(config.enabledModules, ['food']);
      expect(config.foodCategories, contains('Healthy'));
      expect(config.junkFoodCategories, ['Junk', 'Fast Food', 'Sweets']);
      expect(config.isJunkCategory('Junk'), isTrue);
      expect(config.isJunkCategory('Healthy'), isFalse);
    });

    test('fromJson reads valid fields and drops non-string list items', () {
      final config = AppConfig.fromJson({
        'vaultVersion': 2,
        'dailyCalorieGoal': 1850,
        'junkFoodCategories': ['Junk', 42, null],
        'foodCategories': ['Healthy', 'Treats', false],
        'enabledModules': ['food', 'habits'],
      });

      expect(config.vaultVersion, 2);
      expect(config.dailyCalorieGoal, 1850);
      expect(config.junkFoodCategories, ['Junk']);
      expect(config.foodCategories, ['Healthy', 'Treats']);
      expect(config.enabledModules, ['food', 'habits']);
    });

    test('fromJson falls back field by field for malformed values', () {
      final config = AppConfig.fromJson({
        'vaultVersion': 'one',
        'dailyCalorieGoal': 0,
        'junkFoodCategories': 'Junk',
        'foodCategories': 7,
        'enabledModules': null,
      });

      final defaults = AppConfig.defaults();
      expect(config.vaultVersion, defaults.vaultVersion);
      expect(config.dailyCalorieGoal, defaults.dailyCalorieGoal);
      expect(config.junkFoodCategories, defaults.junkFoodCategories);
      expect(config.foodCategories, defaults.foodCategories);
      expect(config.enabledModules, defaults.enabledModules);
    });

    test('copyWith replaces only the supplied fields', () {
      final original = AppConfig.defaults();
      final updated = original.copyWith(
        dailyCalorieGoal: 1500,
        junkFoodCategories: const ['Sweets'],
      );

      expect(updated.dailyCalorieGoal, 1500);
      expect(updated.junkFoodCategories, ['Sweets']);
      expect(updated.vaultVersion, original.vaultVersion);
      expect(updated.foodCategories, original.foodCategories);
      expect(updated.enabledModules, original.enabledModules);
    });

    test('toJson and fromJson round-trip every setting', () {
      final original = AppConfig(
        vaultVersion: 3,
        dailyCalorieGoal: 2400,
        junkFoodCategories: const ['Desserts'],
        foodCategories: const ['Salad', 'Desserts'],
        enabledModules: const ['food', 'running'],
      );

      final restored = AppConfig.fromJson(original.toJson());

      expect(restored.vaultVersion, 3);
      expect(restored.dailyCalorieGoal, 2400);
      expect(restored.junkFoodCategories, ['Desserts']);
      expect(restored.foodCategories, ['Salad', 'Desserts']);
      expect(restored.enabledModules, ['food', 'running']);
    });
  });

  group('FoodEntry', () {
    test('toJson writes an ISO UTC timestamp and round-trips', () {
      final local = DateTime(2026, 11, 23, 8, 30);
      final entry = FoodEntry(
        id: 'entry-1',
        foodName: 'Oatmeal with Banana',
        calories: 320,
        category: 'Healthy',
        timestamp: local,
      );

      final json = entry.toJson();
      expect(json['timestamp'], isA<String>());
      expect(json['timestamp'] as String, endsWith('Z'));

      final restored = FoodEntry.fromJson(json);
      expect(restored.id, entry.id);
      expect(restored.foodName, entry.foodName);
      expect(restored.calories, entry.calories);
      expect(restored.category, entry.category);
      expect(restored.timestamp.isAtSameMomentAs(local), isTrue);
    });

    test('fromJson rejects missing fields and bad timestamps', () {
      expect(
        () => FoodEntry.fromJson({
          'id': 'entry',
          'foodName': 'Soup',
          'category': 'Healthy',
          'timestamp': DateTime(2026, 1, 1).toIso8601String(),
        }),
        throwsFormatException,
      );

      expect(
        () => FoodEntry.fromJson({
          'id': 'entry',
          'foodName': 'Soup',
          'calories': 100,
          'category': 'Healthy',
          'timestamp': 'not-a-date',
        }),
        throwsFormatException,
      );

      expect(
        () => FoodEntry.fromJson({
          'id': 12,
          'foodName': 'Soup',
          'calories': 100,
          'category': 'Healthy',
          'timestamp': DateTime(2026, 1, 1).toIso8601String(),
        }),
        throwsFormatException,
      );
    });

    test('copyWith keeps the current values unless overridden', () {
      final original = FoodEntry(
        id: 'entry-1',
        foodName: 'Oatmeal',
        calories: 300,
        category: 'Healthy',
        timestamp: DateTime(2026, 11, 23, 8),
      );

      final updated = original.copyWith(calories: 350, category: 'Snacks');

      expect(updated.id, original.id);
      expect(updated.foodName, original.foodName);
      expect(updated.timestamp, original.timestamp);
      expect(updated.calories, 350);
      expect(updated.category, 'Snacks');
    });

    test('round-trips optional nutrition, quantity and unit', () {
      final entry = FoodEntry(
        id: 'entry-nutrition',
        foodName: 'Chapati',
        calories: 240,
        category: 'Healthy',
        timestamp: DateTime(2026, 11, 23, 12, 30),
        protein: 6,
        fats: 2.5,
        sugar: 1,
        quantity: 2,
        unit: 'piece',
      );

      final restored = FoodEntry.fromJson(entry.toJson());

      expect(restored.protein, 6);
      expect(restored.fats, 2.5);
      expect(restored.sugar, 1);
      expect(restored.quantity, 2);
      expect(restored.unit, 'piece');
      expect(restored.calories, 240);
    });

    test('older entries without optional fields default to one serving', () {
      final entry = FoodEntry.fromJson({
        'id': 'legacy',
        'foodName': 'Apple',
        'calories': 95,
        'category': 'Healthy',
        'timestamp': '2026-11-23T09:00:00.000Z',
      });

      expect(entry.protein, isNull);
      expect(entry.fats, isNull);
      expect(entry.sugar, isNull);
      expect(entry.quantity, 1);
      expect(entry.unit, isNull);
      expect(entry.comment, isNull);
    });

    test('round-trips an optional comment', () {
      final entry = FoodEntry(
        id: 'entry-comment',
        foodName: 'Oatmeal',
        calories: 300,
        category: 'Healthy',
        timestamp: DateTime(2026, 11, 23, 8, 30),
        comment: 'Post-workout breakfast',
      );

      final restored = FoodEntry.fromJson(entry.toJson());

      expect(restored.comment, 'Post-workout breakfast');
    });

    test('fromJson rejects malformed optional fields', () {
      Map<String, dynamic> base() => {
        'id': 'entry',
        'foodName': 'Soup',
        'calories': 100,
        'category': 'Healthy',
        'timestamp': '2026-11-23T09:00:00.000Z',
      };

      expect(
        () => FoodEntry.fromJson({...base(), 'protein': 'high'}),
        throwsFormatException,
      );
      expect(
        () => FoodEntry.fromJson({...base(), 'fats': 'some'}),
        throwsFormatException,
      );
      expect(
        () => FoodEntry.fromJson({...base(), 'sugar': []}),
        throwsFormatException,
      );
      expect(
        () => FoodEntry.fromJson({...base(), 'quantity': 'two'}),
        throwsFormatException,
      );
      expect(
        () => FoodEntry.fromJson({...base(), 'quantity': -1}),
        throwsFormatException,
      );
      expect(
        () => FoodEntry.fromJson({...base(), 'unit': 3}),
        throwsFormatException,
      );
      expect(
        () => FoodEntry.fromJson({...base(), 'comment': 3}),
        throwsFormatException,
      );
    });
  });

  group('FoodPreset', () {
    test('toJson and fromJson round-trip', () {
      const preset = FoodPreset(
        id: 'preset-1',
        name: 'Greek Yogurt',
        calories: 150,
        defaultCategory: 'Healthy',
      );

      final restored = FoodPreset.fromJson(preset.toJson());

      expect(restored.id, preset.id);
      expect(restored.name, preset.name);
      expect(restored.calories, preset.calories);
      expect(restored.defaultCategory, preset.defaultCategory);
    });

    test('fromJson rejects invalid fields', () {
      expect(
        () => FoodPreset.fromJson({
          'id': 'preset-1',
          'name': 'Yogurt',
          'calories': '150',
          'defaultCategory': 'Healthy',
        }),
        throwsFormatException,
      );
      expect(
        () => FoodPreset.fromJson({'name': 'Yogurt'}),
        throwsFormatException,
      );
    });

    test('copyWith replaces only supplied fields', () {
      const original = FoodPreset(
        id: 'preset-1',
        name: 'Greek Yogurt',
        calories: 150,
        defaultCategory: 'Healthy',
      );

      final updated = original.copyWith(calories: 170);

      expect(updated.id, original.id);
      expect(updated.name, original.name);
      expect(updated.defaultCategory, original.defaultCategory);
      expect(updated.calories, 170);
    });

    test('simple presets keep optional nutrition values', () {
      const preset = FoodPreset(
        id: 'preset-1',
        name: 'Greek Yogurt',
        calories: 150,
        defaultCategory: 'Healthy',
        protein: 10,
        fats: 4.5,
        sugar: 6,
      );

      final restored = FoodPreset.fromJson(preset.toJson());

      expect(restored.type, FoodPresetType.simple);
      expect(restored.protein, 10);
      expect(restored.fats, 4.5);
      expect(restored.sugar, 6);
    });

    test('presets without a type are loaded as simple foods', () {
      final preset = FoodPreset.fromJson({
        'id': 'legacy',
        'name': 'Yogurt',
        'calories': 150,
        'defaultCategory': 'Healthy',
      });

      expect(preset.type, FoodPresetType.simple);
      expect(preset.isGroup, isFalse);
      expect(preset.calories, 150);
    });

    test('group presets total their items and round-trip', () {
      const group = FoodPreset.group(
        id: 'group-lunch',
        name: 'Lunch',
        defaultCategory: 'Healthy',
        items: [
          FoodGroupItem(
            presetId: 'egg',
            name: 'Egg',
            quantity: 5,
            calories: 70,
            protein: 6,
            fats: 5,
            sugar: 0.2,
          ),
          FoodGroupItem(
            presetId: 'chapati',
            name: 'Chapati',
            quantity: 2,
            calories: 120,
            protein: 3,
            fats: 1,
            sugar: 0.5,
          ),
          FoodGroupItem(
            presetId: 'sprouts',
            name: 'Sprouts',
            quantity: 1,
            unit: '100 g',
            calories: 30,
            protein: 3,
            fats: 0.2,
            sugar: 0.5,
          ),
        ],
      );

      expect(group.isGroup, isTrue);
      expect(group.calories, 620);
      expect(group.protein, 39);
      expect(group.fats, closeTo(27.2, 0.0001));
      expect(group.sugar, closeTo(2.5, 0.0001));

      final restored = FoodPreset.fromJson(group.toJson());

      expect(restored.isGroup, isTrue);
      expect(restored.items, hasLength(3));
      expect(restored.items.last.name, 'Sprouts');
      expect(restored.items.last.unit, '100 g');
      expect(restored.items.last.totalCalories, 30);
      expect(restored.calories, 620);
      expect(restored.protein, 39);
      expect(restored.defaultCategory, 'Healthy');
    });

    test('group parsing skips malformed items', () {
      final preset = FoodPreset.fromJson({
        'id': 'group-lunch',
        'name': 'Lunch',
        'defaultCategory': 'Healthy',
        'type': 'group',
        'items': [
          {'presetId': 'egg', 'name': 'Egg', 'quantity': 2, 'calories': 70},
          {'name': 'Broken'},
          'not-a-map',
        ],
      });

      expect(preset.items, hasLength(1));
      expect(preset.items.single.name, 'Egg');
      expect(preset.calories, 140);
    });

    test('fromJson rejects unknown types and group presets without items', () {
      expect(
        () => FoodPreset.fromJson({
          'id': 'preset-1',
          'name': 'Yogurt',
          'calories': 150,
          'defaultCategory': 'Healthy',
          'type': 'meal',
        }),
        throwsFormatException,
      );
      expect(
        () => FoodPreset.fromJson({
          'id': 'preset-1',
          'name': 'Yogurt',
          'defaultCategory': 'Healthy',
          'type': 'group',
        }),
        throwsFormatException,
      );
    });
  });

  group('DailyFoodLog', () {
    FoodEntry entry(
      String id,
      int calories,
      DateTime at, {
      String category = 'Healthy',
    }) {
      return FoodEntry(
        id: id,
        foodName: 'Food $id',
        calories: calories,
        category: category,
        timestamp: at,
      );
    }

    test(
      'sorts newest first, keeps entries unmodifiable and totals calories',
      () {
        final date = DateTime(2026, 11, 23, 18);
        final log = DailyFoodLog(
          date: date,
          entries: [
            entry('morning', 300, DateTime(2026, 11, 23, 8)),
            entry('evening', 500, DateTime(2026, 11, 23, 19), category: 'Junk'),
            entry('noon', 200, DateTime(2026, 11, 23, 12)),
          ],
        );

        expect(log.date, DateTime(2026, 11, 23));
        expect(log.entries.map((item) => item.id), [
          'evening',
          'noon',
          'morning',
        ]);
        expect(
          () => log.entries.add(entry('new', 1, date)),
          throwsUnsupportedError,
        );
        expect(log.totalCalories, 1000);
        expect(log.junkCalories({'Junk'}), 500);
        expect(log.junkCalories({'Sweets'}), 0);
      },
    );

    test('fromJson keeps valid entries and skips malformed ones', () {
      final date = DateTime(2026, 11, 23);
      final log = DailyFoodLog.fromJson({
        'date': '2026-11-23',
        'entries': [
          {
            'id': 'valid',
            'foodName': 'Apple',
            'calories': 95,
            'category': 'Healthy',
            'timestamp': '2026-11-23T09:00:00.000Z',
          },
          {'id': 'missing-calories', 'foodName': 'Mystery'},
          'not-an-object',
        ],
      }, date: date);

      expect(log.entries, hasLength(1));
      expect(log.entries.single.id, 'valid');
      expect(log.date, date);
    });

    test('toJson stores the local date key and entry objects', () {
      final log = DailyFoodLog(
        date: DateTime(2026, 1, 5, 12),
        entries: [entry('one', 100, DateTime(2026, 1, 5, 10))],
      );

      final json = log.toJson();
      expect(json['date'], '2026-01-05');
      expect(json['entries'], hasLength(1));
      expect((json['entries'] as List).single['id'], 'one');
    });
  });

  group('MonthlyFoodLog', () {
    FoodEntry entry(String id, DateTime at, {int calories = 100}) {
      return FoodEntry(
        id: id,
        foodName: 'Food $id',
        calories: calories,
        category: 'Healthy',
        timestamp: at,
      );
    }

    test('sorts entries newest first and filters by day', () {
      final log = MonthlyFoodLog(
        month: DateTime(2026, 11, 23),
        entries: [
          entry('first', DateTime(2026, 11, 22, 8)),
          entry('second', DateTime(2026, 11, 22, 19)),
          entry('third', DateTime(2026, 11, 21, 12)),
        ],
      );

      expect(log.month, DateTime(2026, 11));
      expect(log.entries.map((item) => item.id), ['second', 'first', 'third']);
      expect(
        log.entriesForDate(DateTime(2026, 11, 22)).map((item) => item.id),
        ['second', 'first'],
      );
      expect(log.entriesForDate(DateTime(2026, 11, 20)), isEmpty);
    });

    test('replacing one day keeps the rest of the month', () {
      final log = MonthlyFoodLog(
        month: DateTime(2026, 11),
        entries: [
          entry('keep', DateTime(2026, 11, 21, 9)),
          entry('replace', DateTime(2026, 11, 22, 9)),
        ],
      );

      final updated = log.withEntriesForDate(DateTime(2026, 11, 22), [
        entry('new', DateTime(2026, 11, 22, 20), calories: 250),
      ]);

      expect(updated.entries.map((item) => item.id), ['new', 'keep']);
      expect(updated.entries.first.calories, 250);
      expect(updated.month, DateTime(2026, 11));
    });

    test('toJson and fromJson round-trip and skip malformed entries', () {
      final log = MonthlyFoodLog(
        month: DateTime(2026, 11),
        entries: [entry('valid', DateTime(2026, 11, 23, 8))],
      );

      final restored = MonthlyFoodLog.fromJson(log.toJson(), month: log.month);
      expect(restored.month, DateTime(2026, 11));
      expect(restored.entries.single.id, 'valid');

      final withBadEntries = MonthlyFoodLog.fromJson({
        'month': '2026-11',
        'entries': [
          {
            'id': 'valid',
            'foodName': 'Apple',
            'calories': 95,
            'category': 'Healthy',
            'timestamp': '2026-11-23T09:00:00.000Z',
          },
          {'id': 'bad', 'foodName': 'Mystery'},
          'not-an-object',
        ],
      }, month: DateTime(2026, 11));

      expect(withBadEntries.entries.single.id, 'valid');
    });
  });
}
