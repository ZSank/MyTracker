import 'package:material_ui/material_ui.dart';
import 'package:junk_food_tracker/core/screens/vault_setup_screen.dart';
import 'package:junk_food_tracker/core/services/calorie_reminder_service.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:junk_food_tracker/core/theme/app_theme.dart';
import 'package:junk_food_tracker/features/food/screens/home_screen.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CalorieReminderService.instance.initialize();
  runApp(const JunkFoodTrackerApp());
}

class JunkFoodTrackerApp extends StatelessWidget {
  const JunkFoodTrackerApp({super.key, this.trackerState});

  /// Optional injection point for tests.
  final TrackerState? trackerState;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TrackerState>(
      create: (_) {
        if (trackerState != null) return trackerState!;
        final state = TrackerState();
        CalorieReminderService.instance.attach(state);
        return state..init();
      },
      child: MaterialApp(
        title: 'StrideTracker',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const _StartupGate(),
      ),
    );
  }
}

class _StartupGate extends StatelessWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TrackerState>();

    return switch (state.status) {
      VaultStatus.initializing => const _OpeningVaultScreen(),
      VaultStatus.needsVaultSetup ||
      VaultStatus.error => const VaultSetupScreen(),
      VaultStatus.ready => const HomeScreen(),
    };
  }
}

class _OpeningVaultScreen extends StatelessWidget {
  const _OpeningVaultScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Opening your vault...'),
          ],
        ),
      ),
    );
  }
}
