import 'package:flutter_test/flutter_test.dart';
import 'package:junk_food_tracker/core/models/app_config.dart';
import 'package:junk_food_tracker/features/food/models/daily_food_log.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';

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
}
