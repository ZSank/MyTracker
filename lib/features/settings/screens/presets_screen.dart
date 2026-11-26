import 'package:material_ui/material_ui.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';
import 'package:junk_food_tracker/features/settings/widgets/add_group_dialog.dart';
import 'package:junk_food_tracker/features/settings/widgets/add_preset_dialog.dart';
import 'package:junk_food_tracker/shared/utils/formatters.dart';
import 'package:junk_food_tracker/shared/widgets/category_chip.dart';
import 'package:provider/provider.dart';

/// Full list of pre-made foods, split into single foods and groups.
class PresetsScreen extends StatelessWidget {
  const PresetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TrackerState>();
    final foods = state.presets.where((preset) => !preset.isGroup).toList();
    final groups = state.presets.where((preset) => preset.isGroup).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Pre-made Foods')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SectionHeader(
            title: 'Foods',
            subtitle: foods.isEmpty
                ? 'No single foods yet.'
                : '${foods.length} ${foods.length == 1 ? 'food' : 'foods'}',
          ),
          _PresetSectionCard(
            presets: foods,
            emptyText: 'Add a single food to use it as a quick pick.',
            isJunkCategory: state.isJunkCategory,
            onEdit: (preset) => _editPreset(context, state, preset),
            onDelete: (preset) => _deletePreset(context, state, preset),
          ),
          const SizedBox(height: 24),
          _SectionHeader(
            title: 'Groups',
            subtitle: groups.isEmpty
                ? 'No groups yet.'
                : '${groups.length} ${groups.length == 1 ? 'group' : 'groups'}',
          ),
          _PresetSectionCard(
            presets: groups,
            emptyText: 'Combine foods into a group for one-tap meals.',
            isJunkCategory: state.isJunkCategory,
            onEdit: (preset) => _editPreset(context, state, preset),
            onDelete: (preset) => _deletePreset(context, state, preset),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            key: const Key('add-preset-button'),
            onPressed: () => _addPreset(context, state),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Pre-made Food'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('add-group-button'),
            onPressed: () => _addGroup(context, state),
            icon: const Icon(Icons.lunch_dining_rounded),
            label: const Text('Add Pre-made Food Group'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addPreset(BuildContext context, TrackerState state) async {
    final preset = await showDialog<FoodPreset>(
      context: context,
      builder: (_) => AddPresetDialog(categories: state.foodCategories),
    );
    if (preset == null || !context.mounted) return;
    await state.upsertPreset(preset);
  }

  Future<void> _addGroup(BuildContext context, TrackerState state) async {
    final simplePresets = state.presets
        .where((preset) => !preset.isGroup)
        .toList();

    if (simplePresets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add a pre-made food first, then combine them into a group.',
          ),
        ),
      );
      return;
    }

    final group = await showDialog<FoodPreset>(
      context: context,
      builder: (_) => AddGroupDialog(
        categories: state.foodCategories,
        presets: simplePresets,
      ),
    );
    if (group == null || !context.mounted) return;
    await state.upsertPreset(group);
  }

  Future<void> _editPreset(
    BuildContext context,
    TrackerState state,
    FoodPreset preset,
  ) async {
    final updated = await showDialog<FoodPreset>(
      context: context,
      builder: (_) => preset.isGroup
          ? AddGroupDialog(
              categories: state.foodCategories,
              presets: state.presets.where((item) => !item.isGroup).toList(),
              group: preset,
            )
          : AddPresetDialog(categories: state.foodCategories, preset: preset),
    );
    if (updated == null || !context.mounted) return;
    await state.upsertPreset(updated);
  }

  Future<void> _deletePreset(
    BuildContext context,
    TrackerState state,
    FoodPreset preset,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete pre-made item?'),
        content: Text('Remove "${preset.name}" from your quick picks?'),
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
    if (confirmed != true || !context.mounted) return;

    await state.deletePreset(preset.id);
  }
}

class _PresetSectionCard extends StatelessWidget {
  const _PresetSectionCard({
    required this.presets,
    required this.emptyText,
    required this.isJunkCategory,
    required this.onEdit,
    required this.onDelete,
  });

  final List<FoodPreset> presets;
  final String emptyText;
  final bool Function(String category) isJunkCategory;
  final ValueChanged<FoodPreset> onEdit;
  final ValueChanged<FoodPreset> onDelete;

  @override
  Widget build(BuildContext context) {
    if (presets.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.bookmark_border_rounded),
          title: const Text('Nothing here yet'),
          subtitle: Text(emptyText),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < presets.length; index++) ...[
            if (index > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            _PresetTile(
              preset: presets[index],
              isJunkCategory: isJunkCategory,
              onEdit: () => onEdit(presets[index]),
              onDelete: () => onDelete(presets[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.isJunkCategory,
    required this.onEdit,
    required this.onDelete,
  });

  final FoodPreset preset;
  final bool Function(String category) isJunkCategory;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: preset.isGroup ? const Icon(Icons.lunch_dining_rounded) : null,
      title: Text(preset.name),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CategoryChip(
              category: preset.defaultCategory,
              isJunk: isJunkCategory(preset.defaultCategory),
            ),
            if (!preset.isGroup &&
                (preset.quantity != 1 ||
                    (preset.unit?.trim().isNotEmpty ?? false)))
              Text(
                formatQuantityWithUnit(preset.quantity, preset.unit),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            Text(
              formatCaloriesWithProtein(preset.calories, preset.protein),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            if (preset.isGroup)
              Text(
                '${preset.items.length} items',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('edit-preset-${preset.id}'),
            tooltip: 'Edit pre-made food',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete pre-made food',
            color: colors.error,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      onTap: onEdit,
    );
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
