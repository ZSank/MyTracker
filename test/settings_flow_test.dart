import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';
import 'package:junk_food_tracker/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_vault_service.dart';

void main() {
  const vaultPath = '/virtual/settings-vault';
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

  Future<void> openSettings(WidgetTester tester) async {
    await tester.pumpWidget(JunkFoodTrackerApp(trackerState: trackerState));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-settings-button')));
    await tester.pumpAndSettle();
  }

  Future<void> scrollSettingsTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('daily calorie goal can be changed and persisted', (
    tester,
  ) async {
    await openSettings(tester);

    expect(find.text('2,200 kcal per day'), findsOneWidget);

    await tester.tap(find.text('Daily calorie goal'));
    await tester.pumpAndSettle();

    expect(find.text('Daily Calorie Goal'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('daily-goal-field')), '0');
    await tester.tap(find.byKey(const Key('save-goal-button')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a goal above zero'), findsOneWidget);
    expect(vault.config.dailyCalorieGoal, 2200);

    await tester.enterText(find.byKey(const Key('daily-goal-field')), '1900');
    await tester.tap(find.byKey(const Key('save-goal-button')));
    await tester.pumpAndSettle();

    expect(find.text('Daily Calorie Goal'), findsNothing);
    expect(find.text('1,900 kcal per day'), findsOneWidget);
    expect(trackerState.config.dailyCalorieGoal, 1900);
    expect(vault.config.dailyCalorieGoal, 1900);
  });

  testWidgets('categories can be added, toggled and deleted', (tester) async {
    await openSettings(tester);

    await scrollSettingsTo(tester, find.byKey(const Key('new-category-field')));

    await tester.enterText(
      find.byKey(const Key('new-category-field')),
      'Desserts',
    );
    await tester.tap(find.byKey(const Key('add-category-button')));
    await tester.pumpAndSettle();

    expect(find.text('Desserts'), findsOneWidget);
    expect(trackerState.foodCategories, contains('Desserts'));

    // Duplicate names are rejected case-insensitively by state.
    await tester.enterText(
      find.byKey(const Key('new-category-field')),
      'desserts',
    );
    await tester.tap(find.byKey(const Key('add-category-button')));
    await tester.pumpAndSettle();

    expect(find.text('"desserts" is already a category.'), findsOneWidget);
    expect(
      trackerState.foodCategories.where(
        (category) => category.toLowerCase() == 'desserts',
      ),
      hasLength(1),
    );

    await scrollSettingsTo(tester, find.text('Snacks'));
    final snacksTile = find.ancestor(
      of: find.text('Snacks'),
      matching: find.byType(ListTile),
    );
    final snacksSwitch = find.descendant(
      of: snacksTile,
      matching: find.byType(Switch),
    );

    expect(trackerState.isJunkCategory('Snacks'), isFalse);
    await tester.tap(snacksSwitch);
    await tester.pumpAndSettle();

    expect(trackerState.isJunkCategory('Snacks'), isTrue);
    expect(vault.config.junkFoodCategories, contains('Snacks'));
    expect(
      find.descendant(
        of: snacksTile,
        matching: find.text('Counts as junk food'),
      ),
      findsOneWidget,
    );

    final dessertsTile = find.ancestor(
      of: find.text('Desserts'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: dessertsTile,
        matching: find.byTooltip('Delete category'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete category?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Desserts'), findsNothing);
    expect(trackerState.foodCategories, isNot(contains('Desserts')));
    expect(vault.config.foodCategories, isNot(contains('Desserts')));
  });

  testWidgets('pre-made foods can be deleted after confirmation', (
    tester,
  ) async {
    await trackerState.upsertPreset(
      const FoodPreset(
        id: 'preset-delete',
        name: 'Chocolate Cake',
        calories: 420,
        defaultCategory: 'Junk',
      ),
    );

    await openSettings(tester);
    await scrollSettingsTo(tester, find.text('Chocolate Cake'));

    final presetTile = find.ancestor(
      of: find.text('Chocolate Cake'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: presetTile,
        matching: find.byTooltip('Delete pre-made food'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete pre-made food?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Chocolate Cake'), findsNothing);
    expect(find.text('No pre-made foods yet'), findsOneWidget);
    expect(trackerState.presets, isEmpty);
    expect(vault.presets, isEmpty);
  });

  testWidgets('new pre-made food dialog validates its fields', (tester) async {
    await openSettings(tester);
    await scrollSettingsTo(tester, find.byKey(const Key('add-preset-button')));

    await tester.tap(find.byKey(const Key('add-preset-button')));
    await tester.pumpAndSettle();

    expect(find.text('New Pre-made Food'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-preset-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a food name'), findsOneWidget);
    expect(find.text('Enter calories'), findsOneWidget);
    expect(trackerState.presets, isEmpty);
  });

  testWidgets('settings shows the current vault folder', (tester) async {
    await openSettings(tester);

    expect(find.text('Vault folder'), findsOneWidget);
    expect(find.text(vaultPath), findsOneWidget);
    expect(find.text('Change Vault Folder'), findsOneWidget);
  });
}
