import 'package:material_ui/material_ui.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:junk_food_tracker/features/workout/models/workout_entry.dart';
import 'package:junk_food_tracker/features/workout/widgets/extra_workout_sheet.dart';
import 'package:junk_food_tracker/shared/utils/formatters.dart';
import 'package:provider/provider.dart';

/// Opens the list of today's extra workouts.
Future<void> showExtraWorkoutsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const ExtraWorkoutsSheet(),
  );
}

class ExtraWorkoutsSheet extends StatelessWidget {
  const ExtraWorkoutsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TrackerState>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final workouts = state.todayWorkouts;
    final burned = state.todayBurnedCalories;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Extra Workouts',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            burned > 0
                ? 'Subtracted from today\'s calories. '
                      '${formatNumber(burned)} kcal burned in total.'
                : 'Extra activity is subtracted from today\'s calories.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (workouts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No extra workouts logged today.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final workout in workouts)
              _WorkoutTile(
                workout: workout,
                onEdit: () => showExtraWorkoutSheet(context, entry: workout),
                onDelete: () => _delete(context, workout),
              ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('add-extra-workout-button'),
            onPressed: () => showExtraWorkoutSheet(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Extra Workout'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WorkoutEntry workout) async {
    final state = context.read<TrackerState>();
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete extra workout?'),
        content: Text(
          'Remove "${workout.name}" and add its '
          '${workout.caloriesBurned} kcal back to today\'s total?',
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
    if (confirmed != true) return;

    try {
      await state.deleteWorkoutEntry(workout);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Extra workout removed.'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not remove this workout.\n$error')),
      );
    }
  }
}

class _WorkoutTile extends StatelessWidget {
  const _WorkoutTile({
    required this.workout,
    required this.onEdit,
    required this.onDelete,
  });

  final WorkoutEntry workout;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        child: Icon(
          Icons.local_fire_department_rounded,
          size: 20,
          color: colors.onPrimaryContainer,
        ),
      ),
      title: Text(
        workout.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '${formatEntryTime(workout.timestamp)} · '
        '${formatNumber(workout.caloriesBurned)} kcal burned',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('edit-workout-${workout.id}'),
            tooltip: 'Edit extra workout',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete extra workout',
            color: colors.error,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}
