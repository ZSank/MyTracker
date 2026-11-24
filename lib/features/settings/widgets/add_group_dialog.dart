import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';
import 'package:junk_food_tracker/shared/utils/formatters.dart';
import 'package:uuid/uuid.dart';

/// Builds a grouped pre-made food from existing simple pre-made foods.
class AddGroupDialog extends StatefulWidget {
  const AddGroupDialog({
    super.key,
    required this.categories,
    required this.presets,
    this.group,
  });

  final List<String> categories;

  /// Simple presets that can be added to the group.
  final List<FoodPreset> presets;

  /// When provided, the dialog edits this grouped pre-made food instead of
  /// creating a new one.
  final FoodPreset? group;

  bool get isEditing => group != null;

  @override
  State<AddGroupDialog> createState() => _AddGroupDialogState();
}

class _AddGroupDialogState extends State<AddGroupDialog> {
  static const Uuid _uuid = Uuid();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(
    text: '1',
  );
  final TextEditingController _unitController = TextEditingController();
  late String _category;
  FoodPreset? _selectedPreset;
  List<FoodGroupItem> _items = const [];
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final group = widget.group;
    _category =
        group?.defaultCategory ??
        (widget.categories.isNotEmpty
            ? widget.categories.first
            : 'Uncategorized');
    _items = group?.items ?? const [];
    _nameController.text = group?.name ?? '';
    _selectedPreset = widget.presets.isEmpty ? null : widget.presets.first;
    _fillFromSelectedPreset();
  }

  void _fillFromSelectedPreset() {
    final preset = _selectedPreset;
    if (preset == null) return;
    _quantityController.text = formatQuantity(preset.quantity);
    _unitController.text = preset.unit ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  int get _totalCalories =>
      _items.fold<int>(0, (total, item) => total + item.totalCalories);

  num? get _totalProtein {
    var found = false;
    num total = 0;
    for (final item in _items) {
      final value = item.totalProtein;
      if (value != null) {
        found = true;
        total += value;
      }
    }
    return found ? total : null;
  }

  void _addItem() {
    final preset = _selectedPreset;
    if (preset == null) {
      setState(() => _errorText = 'Choose a pre-made food');
      return;
    }

    final quantity = num.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity <= 0) {
      setState(() => _errorText = 'Enter a quantity above zero');
      return;
    }

    final unit = _unitController.text.trim();
    setState(() {
      _items = [
        ..._items,
        FoodGroupItem(
          presetId: preset.id,
          name: preset.name,
          quantity: quantity,
          baseQuantity: preset.quantity,
          unit: unit.isEmpty ? null : unit,
          calories: preset.calories,
          protein: preset.protein,
          fats: preset.fats,
          sugar: preset.sugar,
        ),
      ];
      _fillFromSelectedPreset();
      _errorText = null;
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items = [..._items]..removeAt(index);
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (_items.isEmpty) {
      setState(() => _errorText = 'Add at least one food to the group');
      return;
    }

    Navigator.of(context).pop(
      FoodPreset.group(
        id: widget.group?.id ?? _uuid.v4(),
        name: _nameController.text.trim(),
        defaultCategory: _category,
        items: List.unmodifiable(_items),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final categories = <String>{...widget.categories, _category}.toList()
      ..sort();

    return AlertDialog(
      title: Text(
        widget.isEditing
            ? 'Edit Pre-made Food Group'
            : 'New Pre-made Food Group',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('group-name-field'),
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Group name',
                    hintText: 'e.g. Lunch',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter a group name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final category in categories)
                      DropdownMenuItem(value: category, child: Text(category)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Foods in this group',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.presets.isEmpty)
                  Text(
                    'Add a single pre-made food first, then come back to '
                    'combine them into a group.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    key: const Key('group-item-preset-field'),
                    initialValue: _selectedPreset?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Pre-made food',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final preset in widget.presets)
                        DropdownMenuItem(
                          value: preset.id,
                          child: Text(
                            '${preset.name} · '
                            '${formatCaloriesWithProtein(preset.calories, preset.protein)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedPreset = widget.presets.firstWhere(
                          (preset) => preset.id == value,
                        );
                        _fillFromSelectedPreset();
                        _errorText = null;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const Key('group-item-quantity-field'),
                          controller: _quantityController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'),
                            ),
                          ],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Weight / quantity',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: const Key('group-item-unit-field'),
                          controller: _unitController,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Unit',
                            hintText: 'g, piece',
                            border: OutlineInputBorder(),
                          ),
                          onFieldSubmitted: (_) => _addItem(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('add-group-item-button'),
                    onPressed: _addItem,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Item'),
                  ),
                ],
                if (_items.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  for (var index = 0; index < _items.length; index++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_items[index].name),
                      subtitle: Text(
                        '${formatQuantityWithUnit(_items[index].quantity, _items[index].unit)}'
                        ' · ${formatCaloriesWithProtein(_items[index].totalCalories, _items[index].totalProtein)}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove ${_items[index].name}',
                        color: colors.error,
                        onPressed: () => _removeItem(index),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Total · ${formatCaloriesWithProtein(_totalCalories, _totalProtein)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                if (_errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorText!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('add-group-confirm'),
          onPressed: _submit,
          child: Text(widget.isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
