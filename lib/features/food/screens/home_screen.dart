import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';
import 'package:junk_food_tracker/features/food/widgets/add_food_sheet.dart';
import 'package:junk_food_tracker/features/settings/screens/settings_screen.dart';
import 'package:junk_food_tracker/features/trends/screens/trends_screen.dart';
import 'package:junk_food_tracker/shared/utils/formatters.dart';
import 'package:junk_food_tracker/shared/widgets/category_chip.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TrackerState>();
    final theme = Theme.of(context);
    final entries = state.recentEntries;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Tracker"),
        actions: [
          IconButton(
            key: const Key('open-trends-button'),
            tooltip: 'Trends',
            icon: const Icon(Icons.insights_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const TrendsScreen()),
              );
            },
          ),
          IconButton(
            key: const Key('open-settings-button'),
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SummaryCard(state: state),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('add-food-entry-button'),
            onPressed: () => showAddFoodSheet(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Food Entry'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              textStyle: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          if (state.lastWriteError != null) ...[
            const SizedBox(height: 12),
            _WriteErrorCard(
              message: state.lastWriteError!,
              onDismiss: state.clearLastWriteError,
            ),
          ],
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'Recent Entries',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                'Last ${TrackerState.recentDays} days',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const _EmptyEntriesCard()
          else
            for (final entry in entries) _EntryCard(entry: entry),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state});

  final TrackerState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final total = state.todayTotalCalories;
    final goal = state.config.dailyCalorieGoal;
    final junk = state.todayJunkCalories;
    final ratio = goal > 0 ? (total / goal).clamp(0.0, 1.0) : 0.0;
    final remaining = goal - total;
    final overGoal = remaining < 0;

    final progressLabel = remaining > 0
        ? '${formatNumber(remaining)} kcal remaining'
        : remaining == 0
        ? 'Daily goal reached'
        : '${formatNumber(-remaining)} kcal over goal';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Today's calories",
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.onPrimaryContainer.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 16,
                      color: colors.onErrorContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${formatNumber(junk)} junk',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: formatNumber(total),
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                TextSpan(
                  text: ' / ${formatNumber(goal)} kcal',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onPrimaryContainer.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              backgroundColor: colors.onPrimaryContainer.withValues(
                alpha: 0.15,
              ),
              valueColor: AlwaysStoppedAnimation<Color>(
                overGoal ? colors.error : colors.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            progressLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: overGoal
                  ? colors.error
                  : colors.onPrimaryContainer.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyEntriesCard extends StatelessWidget {
  const _EmptyEntriesCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Column(
          children: [
            Icon(
              Icons.restaurant_menu_rounded,
              size: 40,
              color: colors.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'No food logged yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap Add Food Entry to log your first meal.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final FoodEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final state = context.read<TrackerState>();
    final isJunk = state.isJunkCategory(entry.category);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey('food-entry-${entry.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.centerRight,
          decoration: BoxDecoration(
            color: colors.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.delete_outline_rounded,
            color: colors.onErrorContainer,
          ),
        ),
        confirmDismiss: (_) => _confirmDelete(context, entry),
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            leading: CircleAvatar(
              backgroundColor: isJunk
                  ? colors.errorContainer
                  : colors.primaryContainer,
              child: Icon(
                isJunk ? Icons.fastfood_rounded : Icons.restaurant_rounded,
                size: 20,
                color: isJunk
                    ? colors.onErrorContainer
                    : colors.onPrimaryContainer,
              ),
            ),
            title: Text(
              entry.foodName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (entry.quantity != 1 ||
                          (entry.unit?.trim().isNotEmpty ?? false))
                        Container(
                          key: ValueKey('entry-quantity-${entry.id}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            formatEntryQuantity(entry),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      CategoryChip(category: entry.category, isJunk: isJunk),
                      Text(
                        formatEntryTime(entry.timestamp),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (entry.items.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.items
                          .map(
                            (item) =>
                                '${item.name} '
                                '${formatQuantityWithUnit(item.quantity, item.unit)}',
                          )
                          .join(' · '),
                      key: ValueKey('entry-items-${entry.id}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (entry.comment?.trim().isNotEmpty ?? false) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.notes_rounded,
                            size: 14,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            entry.comment!.trim(),
                            key: ValueKey('entry-comment-${entry.id}'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            trailing: Text(
              '${formatNumber(entry.calories)} kcal',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            onTap: () => showAddFoodSheet(context, entry: entry),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, FoodEntry entry) async {
    final state = context.read<TrackerState>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      await state.deleteFoodEntry(entry);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not delete ${entry.foodName}.')),
      );
      return false;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text('Removed ${entry.foodName}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(state.addFoodEntry(entry)),
        ),
      ),
    );
    return true;
  }
}

class _WriteErrorCard extends StatelessWidget {
  const _WriteErrorCard({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Could not save to disk.\n$message',
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              icon: Icon(Icons.close_rounded, color: colors.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}
