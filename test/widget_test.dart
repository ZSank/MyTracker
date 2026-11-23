import 'package:flutter_test/flutter_test.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:junk_food_tracker/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_vault_service.dart';

void main() {
  testWidgets('first launch prompts for a vault folder', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const JunkFoodTrackerApp());
    await tester.pumpAndSettle();

    expect(find.text('Set up your vault'), findsOneWidget);
    expect(find.text('Choose Vault Folder'), findsOneWidget);
    expect(find.text('Use Default Location'), findsOneWidget);
  });

  testWidgets('startup gate moves from opening to vault setup', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = TrackerState(vaultService: FakeVaultService());

    await tester.pumpWidget(JunkFoodTrackerApp(trackerState: state));

    expect(find.text('Opening your vault...'), findsOneWidget);

    await state.init();
    await tester.pumpAndSettle();

    expect(find.text('Opening your vault...'), findsNothing);
    expect(find.text('Set up your vault'), findsOneWidget);
  });

  testWidgets('an unreadable vault shows its error on the setup screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final vault = FakeVaultService()..failReads = true;
    final state = TrackerState(vaultService: vault);
    await state.setVaultPath('/virtual/unreadable');

    expect(state.status, VaultStatus.error);

    await tester.pumpWidget(JunkFoodTrackerApp(trackerState: state));
    await tester.pumpAndSettle();

    expect(find.text('Set up your vault'), findsOneWidget);
    expect(find.textContaining('Could not open the vault'), findsOneWidget);
    expect(find.textContaining('Simulated vault read failure'), findsOneWidget);
  });
}
