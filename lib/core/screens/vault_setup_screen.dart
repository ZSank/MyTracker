import 'package:material_ui/material_ui.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:provider/provider.dart';

class VaultSetupScreen extends StatelessWidget {
  const VaultSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TrackerState>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.folder_special_rounded,
                        size: 44,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Set up your vault',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Choose a folder for your tracker data. Everything stays '
                    'in readable JSON files that you can back up, sync, or '
                    'inspect yourself.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (state.errorMessage != null) ...[
                    const SizedBox(height: 24),
                    _ErrorCard(message: state.errorMessage!),
                  ],
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: state.isBusy ? null : state.chooseVaultFolder,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Choose Vault Folder'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: state.isBusy ? null : state.useDefaultVault,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('Use Default Location'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  if (state.isBusy) ...[
                    const SizedBox(height: 20),
                    const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Tip: pick a folder inside iCloud, Drive, or a Syncthing '
                    'directory to keep your data in sync.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
