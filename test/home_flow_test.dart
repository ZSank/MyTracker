import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';
import 'package:junk_food_tracker/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_vault_service.dart';

void main() {
  const vaultPath = '/virtual/tracker-vault';
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

  Future<void> pumpDashboard(WidgetTester tester) async {
    await tester.pumpWidget(JunkFoodTrackerApp(trackerState: trackerState));
    await tester.pumpAndSettle();
  }

  Future<FoodEntry> addTodayEntry({
    required String id,
    required String name,
    required int calories,
    required String category,
    int hour = 12,
    num quantity = 1,
    String? unit,
  }) async {
    final now = DateTime.now();
    final entry = FoodEntry(
      id: id,
      foodName: name,
      calories: calories,
      category: category,
      timestamp: DateTime(now.year, now.month, now.day, hour),
      quantity: quantity,
      unit: unit,
    );
    await trackerState.addFoodEntry(entry);
    return entry;
  }

  // The provider owns the injected state and disposes it with the widget tree.

  testWidgets('dashboard logs a custom food entry', (tester) async {
    await pumpDashboard(tester);

    expect(find.text("Today's Tracker"), findsOneWidget);
    expect(find.text('No food logged yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-food-entry-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('food-name-field')),
      'Custom Meal',
    );
    await tester.enterText(find.byKey(const Key('calories-field')), '450');
    await tester.ensureVisible(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();

    expect(find.text('Custom Meal'), findsOneWidget);
    expect(find.text('450 kcal'), findsOneWidget);
    expect(find.text('No food logged yet'), findsNothing);

    final log = vault.logs[dateKey(DateTime.now())];
    expect(log, isNotNull);
    expect(log!.entries.single.foodName, 'Custom Meal');
    expect(log.entries.single.calories, 450);
  });

  testWidgets('dashboard saves and shows an entry comment', (tester) async {
    await pumpDashboard(tester);

    await tester.tap(find.byKey(const Key('add-food-entry-button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('food-name-field')), 'Salad');
    await tester.enterText(find.byKey(const Key('calories-field')), '250');
    await tester.ensureVisible(find.byKey(const Key('comment-field')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('comment-field')),
      'Lunch with friends',
    );

    await tester.ensureVisible(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();

    final log = vault.logs[dateKey(DateTime.now())];
    expect(log, isNotNull);
    final entry = log!.entries.single;
    expect(entry.comment, 'Lunch with friends');
    expect(find.byKey(ValueKey('entry-comment-${entry.id}')), findsOneWidget);
    expect(find.text('Lunch with friends'), findsOneWidget);
  });

  testWidgets('timing shortcuts set yesterday and a time of day', (
    tester,
  ) async {
    await pumpDashboard(tester);

    await tester.tap(find.byKey(const Key('add-food-entry-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('food-name-field')),
      'Late snack',
    );
    await tester.enterText(find.byKey(const Key('calories-field')), '150');

    await tester.ensureVisible(find.byKey(const Key('timing-yesterday-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timing-yesterday-chip')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('timing-night-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timing-night-chip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('custom-timing-button')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1, 21);
    final log = vault.logs[dateKey(yesterday)];
    expect(log, isNotNull);
    final entry = log!.entries.single;
    expect(entry.foodName, 'Late snack');
    expect(entry.timestamp.year, yesterday.year);
    expect(entry.timestamp.month, yesterday.month);
    expect(entry.timestamp.day, yesterday.day);
    expect(entry.timestamp.hour, 21);
  });

  testWidgets('dashboard adds a pre-made food in one tap', (tester) async {
    await trackerState.upsertPreset(
      const FoodPreset(
        id: 'preset-1',
        name: 'Greek Yogurt',
        calories: 150,
        defaultCategory: 'Healthy',
      ),
    );

    await pumpDashboard(tester);

    await tester.tap(find.byKey(const Key('add-food-entry-button')));
    await tester.pumpAndSettle();

    expect(find.text('Pre-made foods'), findsOneWidget);
    await tester.tap(find.textContaining('Greek Yogurt'));
    await tester.pumpAndSettle();

    expect(find.text('Greek Yogurt'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();

    final log = vault.logs[dateKey(DateTime.now())];
    expect(log, isNotNull);
    expect(log!.entries.single.foodName, 'Greek Yogurt');
    expect(log.entries.single.calories, 150);
    expect(log.entries.single.category, 'Healthy');
  });

  testWidgets('pre-made food nutrition scales with the entry quantity', (
    tester,
  ) async {
    await trackerState.upsertPreset(
      const FoodPreset(
        id: 'preset-chapati',
        name: 'Chapati',
        calories: 120,
        defaultCategory: 'Healthy',
        protein: 3,
        fats: 1,
        sugar: 0.5,
      ),
    );

    await pumpDashboard(tester);

    await tester.tap(find.byKey(const Key('add-food-entry-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Chapati'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quantity-field')), '2');
    await tester.pumpAndSettle();

    String fieldText(Key key) {
      return tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;
    }

    expect(fieldText(const Key('calories-field')), '240');
    expect(fieldText(const Key('protein-field')), '6');
    expect(fieldText(const Key('fats-field')), '2');
    expect(fieldText(const Key('sugar-field')), '1');

    await tester.ensureVisible(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();

    final log = vault.logs[dateKey(DateTime.now())];
    expect(log, isNotNull);
    final entry = log!.entries.single;
    expect(entry.quantity, 2);
    expect(entry.calories, 240);
    expect(entry.protein, 6);
    expect(entry.fats, 2);
    expect(entry.sugar, 1);
  });

  testWidgets('group pre-made food shows its contents and logs the total', (
    tester,
  ) async {
    await trackerState.upsertPreset(
      const FoodPreset.group(
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
          ),
          FoodGroupItem(
            presetId: 'chapati',
            name: 'Chapati',
            quantity: 2,
            calories: 120,
            protein: 3,
          ),
        ],
      ),
    );

    await pumpDashboard(tester);

    await tester.tap(find.byKey(const Key('add-food-entry-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Lunch ·'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('group-contents-group-lunch')),
      findsOneWidget,
    );
    expect(find.text('Group contents · 2 items'), findsOneWidget);
    expect(find.textContaining('5 · Egg'), findsOneWidget);
    expect(find.textContaining('2 · Chapati'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();

    final log = vault.logs[dateKey(DateTime.now())];
    expect(log, isNotNull);
    final entry = log!.entries.single;
    expect(entry.foodName, 'Lunch');
    expect(entry.calories, 590);
    expect(entry.protein, 36);
    expect(find.text('590 kcal'), findsOneWidget);
  });

  testWidgets('dashboard summary shows totals, junk and remaining goal', (
    tester,
  ) async {
    await addTodayEntry(
      id: 'summary-1',
      name: 'Chicken Salad',
      calories: 1200,
      category: 'Healthy',
      hour: 8,
    );
    await addTodayEntry(
      id: 'summary-2',
      name: 'Chocolate Bar',
      calories: 350,
      category: 'Junk',
      hour: 12,
    );

    await pumpDashboard(tester);

    expect(find.textContaining('1,550 / 2,200 kcal'), findsOneWidget);
    expect(find.text('350 junk'), findsOneWidget);
    expect(find.text('650 kcal remaining'), findsOneWidget);
    expect(find.text('Chicken Salad'), findsOneWidget);
    expect(find.text('Chocolate Bar'), findsOneWidget);
    expect(find.text('No food logged yet'), findsNothing);
  });

  testWidgets('entry cards show a quantity and unit badge', (tester) async {
    await addTodayEntry(
      id: 'quantity-entry',
      name: 'Chapati',
      calories: 240,
      category: 'Healthy',
      hour: 12,
      quantity: 2,
      unit: 'pieces',
    );

    await pumpDashboard(tester);

    expect(
      find.byKey(const ValueKey('entry-quantity-quantity-entry')),
      findsOneWidget,
    );
    expect(find.text('2 pieces'), findsOneWidget);
  });

  testWidgets('add food form requires a name and calories', (tester) async {
    await pumpDashboard(tester);

    await tester.tap(find.byKey(const Key('add-food-entry-button')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a food name'), findsOneWidget);
    expect(find.text('Enter calories'), findsOneWidget);
    expect(vault.logs, isEmpty);
    expect(find.byKey(const Key('save-entry-button')), findsOneWidget);
  });

  testWidgets('add food form can save the entry as a pre-made food', (
    tester,
  ) async {
    await pumpDashboard(tester);

    await tester.tap(find.byKey(const Key('add-food-entry-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('food-name-field')),
      'Chicken Wrap',
    );
    await tester.enterText(find.byKey(const Key('calories-field')), '520');
    await tester.ensureVisible(find.text('Save as pre-made food'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as pre-made food'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();

    expect(vault.presets, hasLength(1));
    expect(vault.presets.single.name, 'Chicken Wrap');
    expect(vault.presets.single.calories, 520);
    expect(vault.presets.single.defaultCategory, 'Healthy');

    await tester.tap(find.byKey(const Key('add-food-entry-button')));
    await tester.pumpAndSettle();
    expect(find.text('Chicken Wrap · 520 kcal'), findsOneWidget);
  });

  testWidgets('saving a multi-serving entry stores per-serving preset values', (
    tester,
  ) async {
    await pumpDashboard(tester);

    await tester.tap(find.byKey(const Key('add-food-entry-button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('food-name-field')), 'Chapati');
    await tester.enterText(find.byKey(const Key('calories-field')), '240');
    await tester.enterText(find.byKey(const Key('quantity-field')), '2');
    await tester.enterText(find.byKey(const Key('protein-field')), '6');
    await tester.enterText(find.byKey(const Key('fats-field')), '2');
    await tester.enterText(find.byKey(const Key('sugar-field')), '1');

    await tester.ensureVisible(find.text('Save as pre-made food'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as pre-made food'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();

    final preset = vault.presets.single;
    expect(preset.name, 'Chapati');
    expect(preset.calories, 120);
    expect(preset.protein, 3);
    expect(preset.fats, 1);
    expect(preset.sugar, 0.5);

    final log = vault.logs[dateKey(DateTime.now())];
    expect(log, isNotNull);
    expect(log!.entries.single.quantity, 2);
    expect(log.entries.single.calories, 240);
  });

  testWidgets('add food form saves the selected category', (tester) async {
    await pumpDashboard(tester);

    await tester.tap(find.byKey(const Key('add-food-entry-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('food-name-field')),
      'Candy Bar',
    );
    await tester.enterText(find.byKey(const Key('calories-field')), '250');

    await tester.tap(find.text('Healthy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Junk').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();

    final log = vault.logs[dateKey(DateTime.now())];
    expect(log, isNotNull);
    expect(log!.entries.single.category, 'Junk');
    expect(find.text('Candy Bar'), findsOneWidget);
    expect(find.text('250 junk'), findsOneWidget);
  });

  testWidgets('tapping an entry opens an edit form and saves changes', (
    tester,
  ) async {
    final entry = await addTodayEntry(
      id: 'editable',
      name: 'Oatmeal',
      calories: 300,
      category: 'Healthy',
      hour: 8,
    );

    await pumpDashboard(tester);

    await tester.tap(find.text('Oatmeal'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Food Entry'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('food-name-field')),
      'Oatmeal and Berries',
    );
    await tester.enterText(find.byKey(const Key('calories-field')), '350');
    await tester.ensureVisible(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();

    expect(find.text('Oatmeal and Berries'), findsOneWidget);
    expect(find.text('350 kcal'), findsOneWidget);
    expect(find.text('Oatmeal'), findsNothing);

    final log = vault.logs[dateKey(entry.timestamp)];
    expect(log, isNotNull);
    expect(log!.entries.single.id, 'editable');
    expect(log.entries.single.foodName, 'Oatmeal and Berries');
    expect(log.entries.single.calories, 350);
  });

  testWidgets('swiping an entry deletes it and undo restores it', (
    tester,
  ) async {
    final entry = await addTodayEntry(
      id: 'delete-me',
      name: 'Banana',
      calories: 100,
      category: 'Healthy',
      hour: 9,
    );

    await pumpDashboard(tester);
    expect(find.byKey(const ValueKey('food-entry-delete-me')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('food-entry-delete-me')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('food-entry-delete-me')), findsNothing);
    expect(find.textContaining('Removed Banana'), findsOneWidget);
    expect(trackerState.todayEntries, isEmpty);
    expect(vault.logs[dateKey(entry.timestamp)]!.entries, isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('food-entry-delete-me')), findsOneWidget);
    expect(trackerState.todayEntries, hasLength(1));
    expect(vault.logs[dateKey(entry.timestamp)]!.entries, hasLength(1));
  });

  testWidgets('write failures show a dismissible dashboard banner', (
    tester,
  ) async {
    vault.failWrites = true;
    await addTodayEntry(
      id: 'write-failure',
      name: 'Toast',
      calories: 120,
      category: 'Healthy',
      hour: 8,
    );

    await pumpDashboard(tester);

    expect(find.textContaining('Could not save to disk.'), findsOneWidget);
    expect(trackerState.lastWriteError, isNotNull);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not save to disk.'), findsNothing);
    expect(trackerState.lastWriteError, isNull);
  });

  testWidgets('settings add a category and a pre-made food', (tester) async {
    await pumpDashboard(tester);

    await tester.tap(find.byKey(const Key('open-settings-button')));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Food Categories'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('new-category-field')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('new-category-field')),
      'Desserts',
    );
    await tester.tap(find.byKey(const Key('add-category-button')));
    await tester.pumpAndSettle();

    expect(find.text('Desserts'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('add-preset-button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Pre-made Foods'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-preset-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('preset-name-field')),
      'Chocolate Cake',
    );
    await tester.enterText(
      find.byKey(const Key('preset-calories-field')),
      '420',
    );
    await tester.tap(find.byKey(const Key('add-preset-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Chocolate Cake'), findsOneWidget);

    expect(vault.config.foodCategories, contains('Desserts'));
    expect(vault.presets.single.name, 'Chocolate Cake');
    expect(vault.presets.single.calories, 420);
  });
}
