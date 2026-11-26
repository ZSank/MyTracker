import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:junk_food_tracker/features/workout/models/workout_entry.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

/// Opens the form used to log or edit an extra workout.
Future<void> showExtraWorkoutSheet(
  BuildContext context, {
  WorkoutEntry? entry,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ExtraWorkoutSheet(entry: entry),
  );
}

class _WorkoutPreset {
  const _WorkoutPreset(this.label, this.calories);

  final String label;
  final int calories;
}

const List<_WorkoutPreset> _presets = [
  _WorkoutPreset('Walk · 30 min', 150),
  _WorkoutPreset('Walk · 1 hour', 300),
  _WorkoutPreset('Run · 30 min', 300),
  _WorkoutPreset('Cycle · 30 min', 250),
];

class ExtraWorkoutSheet extends StatefulWidget {
  const ExtraWorkoutSheet({super.key, this.entry});

  final WorkoutEntry? entry;

  @override
  State<ExtraWorkoutSheet> createState() => _ExtraWorkoutSheetState();
}

class _ExtraWorkoutSheetState extends State<ExtraWorkoutSheet> {
  static const Uuid _uuid = Uuid();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _caloriesController;
  bool _saving = false;

  bool get _isEditing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.entry?.name ?? '');
    _caloriesController = TextEditingController(
      text: widget.entry?.caloriesBurned.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesController.dispose();
    super.dispose();
  }

  void _applyPreset(_WorkoutPreset preset) {
    _nameController.text = preset.label;
    _caloriesController.text = preset.calories.toString();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final state = context.read<TrackerState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);

    try {
      final calories = int.parse(_caloriesController.text.trim());
      final name = _nameController.text.trim().isEmpty
          ? 'Extra workout'
          : _nameController.text.trim();

      await state.saveWorkoutEntry(
        WorkoutEntry(
          id: widget.entry?.id ?? _uuid.v4(),
          name: name,
          caloriesBurned: calories,
          timestamp: widget.entry?.timestamp ?? DateTime.now(),
        ),
      );

      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Extra workout saved.'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save this workout.\n$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final entry = widget.entry;
    if (entry == null || _saving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete extra workout?'),
        content: Text(
          'Remove "${entry.name}" and add its '
          '${entry.caloriesBurned} kcal back to today\'s total?',
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
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);

    try {
      await state.deleteWorkoutEntry(entry);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Extra workout removed.'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not remove this workout.\n$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEditing ? 'Edit Extra Workout' : 'Log Extra Workout',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Subtracted from today\'s food calories. It is not logged '
                  'as a meal.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Quick picks',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in _presets)
                      ActionChip(
                        key: Key('workout-preset-${preset.label}'),
                        avatar: const Icon(
                          Icons.local_fire_department_rounded,
                          size: 18,
                        ),
                        label: Text(
                          '${preset.label} · ${preset.calories} kcal',
                        ),
                        onPressed: _saving ? null : () => _applyPreset(preset),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('workout-name-field'),
                  controller: _nameController,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: 'e.g. Evening walk',
                    prefixIcon: Icon(Icons.directions_walk_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('workout-calories-field'),
                  controller: _caloriesController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                  decoration: const InputDecoration(
                    labelText: 'Calories burned',
                    hintText: 'e.g. 200',
                    prefixIcon: Icon(Icons.local_fire_department_rounded),
                    suffixText: 'kcal',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Enter calories burned';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('save-workout-button'),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(
                    _saving
                        ? 'Saving...'
                        : _isEditing
                        ? 'Save Changes'
                        : 'Save Extra Workout',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
                if (_isEditing) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: const Key('delete-workout-button'),
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete extra workout'),
                    style: TextButton.styleFrom(foregroundColor: colors.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
