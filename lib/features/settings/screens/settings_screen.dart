import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:junk_food_tracker/core/services/calorie_reminder_service.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:junk_food_tracker/features/settings/screens/feature_requests_screen.dart';
import 'package:junk_food_tracker/features/settings/screens/presets_screen.dart';
import 'package:junk_food_tracker/shared/utils/formatters.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _categoryController = TextEditingController();
  bool _changingVault = false;

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TrackerState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _SectionHeader(
            title: 'Vault',
            subtitle: 'Your data lives in human-readable JSON files.',
          ),
          _buildVaultCard(state),
          const SizedBox(height: 24),
          const _SectionHeader(title: 'Daily Goal'),
          _buildGoalCard(state),
          const SizedBox(height: 24),
          const _SectionHeader(
            title: 'Daily Reminder',
            subtitle: 'Get a notification with the calories logged that day.',
          ),
          _buildReminderCard(state),
          const SizedBox(height: 24),
          const _SectionHeader(
            title: 'Food Categories',
            subtitle: 'Toggle which categories count as junk food.',
          ),
          _buildCategoriesCard(state),
          const SizedBox(height: 24),
          const _SectionHeader(
            title: 'Pre-made Foods',
            subtitle: 'Quick picks shown when adding an entry.',
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: const Key('open-presets-button'),
              leading: Icon(
                Icons.bookmark_border_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Pre-made foods and groups'),
              subtitle: Text(
                state.presets.isEmpty
                    ? 'No pre-made foods yet.'
                    : '${state.presets.where((preset) => !preset.isGroup).length} '
                          'foods · '
                          '${state.presets.where((preset) => preset.isGroup).length} '
                          'groups',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PresetsScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          const _SectionHeader(
            title: 'Feature Requests',
            subtitle:
                'Write down features you want to add. Saved in your vault.',
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: const Key('open-feature-requests-button'),
              leading: Icon(
                Icons.lightbulb_outline_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Feature request notes'),
              subtitle: const Text(
                'Open feature_requests.txt from your vault folder.',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FeatureRequestsScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVaultCard(TrackerState state) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_rounded, color: colors.primary),
                    const SizedBox(width: 10),
                    Text(
                      'Vault folder',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  state.vaultPath ?? 'Not configured',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: OutlinedButton.icon(
              key: const Key('change-vault-button'),
              onPressed: (_changingVault || state.isBusy) ? null : _changeVault,
              icon: _changingVault
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.drive_folder_upload_rounded),
              label: const Text('Change Vault Folder'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Switching folders does not delete the old vault. Each folder '
              'keeps its own JSON files. Choose the folder that already '
              'contains your vault data so the app can keep access to it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalCard(TrackerState state) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.flag_rounded),
        title: const Text('Daily calorie goal'),
        subtitle: Text(
          '${formatNumber(state.config.dailyCalorieGoal)} kcal per day',
        ),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => _editGoal(state.config.dailyCalorieGoal),
      ),
    );
  }

  Widget _buildReminderCard(TrackerState state) {
    final config = state.config;
    final timeLabel = TimeOfDay(
      hour: config.dailyReminderHour,
      minute: config.dailyReminderMinute,
    ).format(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            key: const Key('daily-reminder-switch'),
            secondary: Icon(
              config.dailyReminderEnabled
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_outlined,
            ),
            title: const Text('Daily calorie reminder'),
            subtitle: Text(
              config.dailyReminderEnabled
                  ? "Today's total is sent at $timeLabel."
                  : 'Off',
            ),
            value: config.dailyReminderEnabled,
            onChanged: (value) => unawaited(_setReminderEnabled(state, value)),
          ),
          if (config.dailyReminderEnabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              key: const Key('daily-reminder-time-tile'),
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Reminder time'),
              subtitle: Text(timeLabel),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => unawaited(_pickReminderTime(state)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoriesCard(TrackerState state) {
    final categories = state.foodCategories;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (categories.isEmpty)
            const ListTile(
              leading: Icon(Icons.category_outlined),
              title: Text('No categories yet'),
            )
          else
            for (var index = 0; index < categories.length; index++) ...[
              if (index > 0)
                const Divider(height: 1, indent: 16, endIndent: 16),
              _buildCategoryTile(state, categories[index]),
            ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('new-category-field'),
                    controller: _categoryController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'New category',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addCategory(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('add-category-button'),
                  onPressed: _addCategory,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(72, 48),
                  ),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTile(TrackerState state, String category) {
    final colors = Theme.of(context).colorScheme;
    final isJunk = state.isJunkCategory(category);

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      title: Text(category),
      subtitle: Text(
        isJunk ? 'Counts as junk food' : 'Not counted as junk food',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: isJunk,
            onChanged: (value) {
              unawaited(state.setCategoryCountsAsJunk(category, value));
            },
          ),
          IconButton(
            tooltip: 'Delete category',
            color: colors.error,
            onPressed: () => _deleteCategory(category),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _changeVault() async {
    final state = context.read<TrackerState>();
    final previousPath = state.vaultPath;

    setState(() => _changingVault = true);
    try {
      await state.chooseVaultFolder();
    } finally {
      if (mounted) setState(() => _changingVault = false);
    }

    if (!mounted) return;
    if (state.errorMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(state.errorMessage!)));
    } else if (state.vaultPath != previousPath) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Vault folder updated.')));
    }
  }

  Future<void> _editGoal(int currentGoal) async {
    final state = context.read<TrackerState>();
    final goal = await showDialog<int>(
      context: context,
      builder: (_) => _CalorieGoalDialog(initialGoal: currentGoal),
    );
    if (goal == null || !mounted) return;
    await state.setDailyCalorieGoal(goal);
  }

  Future<void> _setReminderEnabled(TrackerState state, bool enabled) async {
    if (enabled) {
      final allowed = await CalorieReminderService.instance.requestPermission();
      if (!mounted) return;
      if (!allowed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notifications are blocked. Allow them for StrideTracker in '
              'system settings to receive reminders.',
            ),
          ),
        );
        return;
      }
    }

    await state.setDailyReminderEnabled(enabled);
  }

  Future<void> _pickReminderTime(TrackerState state) async {
    final config = state.config;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: config.dailyReminderHour,
        minute: config.dailyReminderMinute,
      ),
      helpText: 'Daily reminder time',
    );
    if (picked == null || !mounted) return;
    await state.setDailyReminderTime(picked.hour, picked.minute);
  }

  Future<void> _addCategory() async {
    final value = _categoryController.text.trim();
    if (value.isEmpty) return;

    FocusScope.of(context).unfocus();
    final state = context.read<TrackerState>();
    final added = await state.addFoodCategory(value);

    if (!mounted) return;
    if (added) {
      _categoryController.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$value" is already a category.')),
      );
    }
  }

  Future<void> _deleteCategory(String category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          'Remove "$category"? Existing entries and pre-made foods that use '
          'this category keep their label.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final state = context.read<TrackerState>();
    final removed = await state.removeFoodCategory(category);
    if (!mounted) return;
    if (!removed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keep at least one food category.')),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CalorieGoalDialog extends StatefulWidget {
  const _CalorieGoalDialog({required this.initialGoal});

  final int initialGoal;

  @override
  State<_CalorieGoalDialog> createState() => _CalorieGoalDialogState();
}

class _CalorieGoalDialogState extends State<_CalorieGoalDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialGoal.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final goal = int.tryParse(_controller.text.trim());
    if (goal == null) return;
    Navigator.of(context).pop(goal);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Daily Calorie Goal'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('daily-goal-field'),
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Goal',
            suffixText: 'kcal',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            final goal = int.tryParse(value?.trim() ?? '');
            if (goal == null || goal <= 0) return 'Enter a goal above zero';
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('save-goal-button'),
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
