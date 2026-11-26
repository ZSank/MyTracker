import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';
import 'package:junk_food_tracker/shared/utils/formatters.dart';
import 'package:junk_food_tracker/shared/utils/json_clipboard.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

/// Quick time-of-day shortcuts for the entry form.
enum _DayPeriod {
  morning('Morning', 8),
  afternoon('Afternoon', 13),
  evening('Evening', 18),
  night('Night', 21);

  const _DayPeriod(this.label, this.hour);

  final String label;
  final int hour;

  static _DayPeriod forHour(int hour) {
    if (hour >= 5 && hour < 12) return morning;
    if (hour >= 12 && hour < 17) return afternoon;
    if (hour >= 17 && hour < 21) return evening;
    return night;
  }
}

Future<void> showAddFoodSheet(BuildContext context, {FoodEntry? entry}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => AddFoodSheet(entry: entry),
  );
}

class AddFoodSheet extends StatefulWidget {
  const AddFoodSheet({super.key, this.entry});

  final FoodEntry? entry;

  @override
  State<AddFoodSheet> createState() => _AddFoodSheetState();
}

class _AddFoodSheetState extends State<AddFoodSheet> {
  static const Uuid _uuid = Uuid();
  static const int _recentPresetLimit = 5;
  static const int _suggestionLimit = 6;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FocusNode _nameFocusNode = FocusNode();
  late final TextEditingController _nameController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _quantityController;
  late final TextEditingController _unitController;
  late final TextEditingController _proteinController;
  late final TextEditingController _fatsController;
  late final TextEditingController _sugarController;
  late final TextEditingController _commentController;
  late DateTime _timestamp;
  String? _category;
  List<FoodGroupItem> _items = const <FoodGroupItem>[];
  String? _selectedGroupId;
  bool _saveAsPreset = false;
  bool _saving = false;
  bool _nameEdited = false;

  bool get _isEditing => widget.entry != null;

  bool get _hasItems => _items.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final state = context.read<TrackerState>();
    final entry = widget.entry;

    _nameController = TextEditingController(text: entry?.foodName ?? '');
    _caloriesController = TextEditingController(
      text: entry == null ? '' : entry.calories.toString(),
    );
    _quantityController = TextEditingController(
      text: entry == null ? '1' : formatQuantity(entry.quantity),
    );
    _unitController = TextEditingController(text: entry?.unit ?? '');
    _proteinController = TextEditingController(
      text: _optionalText(entry?.protein),
    );
    _fatsController = TextEditingController(text: _optionalText(entry?.fats));
    _sugarController = TextEditingController(text: _optionalText(entry?.sugar));
    _commentController = TextEditingController(text: entry?.comment ?? '');
    _timestamp = entry?.timestamp ?? DateTime.now();

    final fallbackCategory = state.foodCategories.isNotEmpty
        ? state.foodCategories.first
        : 'Uncategorized';
    _category = entry?.category ?? fallbackCategory;

    if (entry != null) {
      _items = List<FoodGroupItem>.unmodifiable(entry.items);
      _nameEdited = true;
      final presetId = entry.presetId;
      if (presetId != null) {
        for (final preset in state.presets) {
          if (preset.id == presetId && preset.isGroup) {
            _selectedGroupId = preset.id;
            break;
          }
        }
      }
      if (_items.isNotEmpty) _syncTotalsFromItems();
    }

    _nameFocusNode.addListener(_handleNameFocusChanged);
  }

  @override
  void dispose() {
    _nameFocusNode.removeListener(_handleNameFocusChanged);
    _nameFocusNode.dispose();
    _nameController.dispose();
    _caloriesController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    _proteinController.dispose();
    _fatsController.dispose();
    _sugarController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  static String _optionalText(num? value) =>
      value == null ? '' : formatQuantity(value);

  num? _parsedQuantity(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return num.tryParse(text);
  }

  num? _optionalValue(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return num.tryParse(text);
  }

  void _handleNameFocusChanged() {
    if (mounted) setState(() {});
  }

  int get _itemsCalories =>
      _items.fold<int>(0, (total, item) => total + item.totalCalories);

  num? get _itemsProtein => _sumItemOptional((item) => item.totalProtein);

  num? _sumItemOptional(num? Function(FoodGroupItem item) read) {
    var found = false;
    num total = 0;
    for (final item in _items) {
      final value = read(item);
      if (value != null) {
        found = true;
        total += value;
      }
    }
    return found ? total : null;
  }

  void _syncTotalsFromItems() {
    if (_items.isEmpty) return;
    _caloriesController.text = _itemsCalories.toString();
    _proteinController.text = _optionalText(
      _sumItemOptional((item) => item.totalProtein),
    );
    _fatsController.text = _optionalText(
      _sumItemOptional((item) => item.totalFats),
    );
    _sugarController.text = _optionalText(
      _sumItemOptional((item) => item.totalSugar),
    );
  }

  void _clearAutoTotals() {
    _caloriesController.clear();
    _proteinController.clear();
    _fatsController.clear();
    _sugarController.clear();
  }

  FoodGroupItem _itemFromPreset(FoodPreset preset) {
    final base = preset.quantity > 0 ? preset.quantity : 1;
    return FoodGroupItem(
      presetId: preset.id,
      name: preset.name,
      quantity: base,
      baseQuantity: base,
      unit: preset.unit,
      calories: preset.calories,
      protein: preset.protein,
      fats: preset.fats,
      sugar: preset.sugar,
    );
  }

  String _autoEntryName(TrackerState state) {
    if (_selectedGroupId != null) {
      for (final preset in state.presets) {
        if (preset.id == _selectedGroupId) return preset.name;
      }
    }
    if (_items.isEmpty) return '';
    if (_items.length == 1) return _items.single.name;
    return _items.map((item) => item.name).join(' + ');
  }

  void _refreshAutoName(TrackerState state) {
    if (_nameEdited) return;
    final next = _autoEntryName(state);
    if (next.isEmpty) return;
    if (_nameController.text != next) _nameController.text = next;
  }

  void _selectPreset(FoodPreset preset, {bool fromSuggestion = false}) {
    final state = context.read<TrackerState>();

    if (preset.isGroup) {
      setState(() {
        _selectedGroupId = preset.id;
        _items = List<FoodGroupItem>.unmodifiable(preset.items);
        _category = preset.defaultCategory;
        if (fromSuggestion || !_nameEdited) {
          _nameEdited = false;
          _nameController.text = preset.name;
        }
        if (_items.isEmpty) {
          _clearAutoTotals();
        } else {
          _syncTotalsFromItems();
        }
      });
      return;
    }

    final isSelected = _items.any((item) => item.presetId == preset.id);
    setState(() {
      if (isSelected) {
        _items = List<FoodGroupItem>.unmodifiable(
          _items.where((item) => item.presetId != preset.id),
        );
        if (_items.isEmpty) {
          _selectedGroupId = null;
          _clearAutoTotals();
        } else {
          _syncTotalsFromItems();
        }
        _refreshAutoName(state);
      } else {
        final hadItems = _items.isNotEmpty;
        _items = List<FoodGroupItem>.unmodifiable([
          ..._items,
          _itemFromPreset(preset),
        ]);
        if (!hadItems) _category = preset.defaultCategory;
        if (fromSuggestion || !_nameEdited) {
          _nameEdited = false;
          _refreshAutoName(state);
        }
        _syncTotalsFromItems();
      }
    });
  }

  void _updateItemQuantity(int index, num quantity) {
    if (index < 0 || index >= _items.length) return;
    final state = context.read<TrackerState>();
    setState(() {
      final next = [..._items];
      next[index] = next[index].copyWith(quantity: quantity);
      _items = List<FoodGroupItem>.unmodifiable(next);
      _syncTotalsFromItems();
      _refreshAutoName(state);
    });
  }

  void _removeItem(int index) {
    if (index < 0 || index >= _items.length) return;
    final state = context.read<TrackerState>();
    setState(() {
      final next = [..._items]..removeAt(index);
      _items = List<FoodGroupItem>.unmodifiable(next);
      if (_items.isEmpty) {
        _selectedGroupId = null;
        _clearAutoTotals();
      } else {
        _syncTotalsFromItems();
      }
      _refreshAutoName(state);
    });
  }

  Future<void> _openPresetPicker() async {
    final state = context.read<TrackerState>();
    if (state.presets.isEmpty) return;

    final preset = await showModalBottomSheet<FoodPreset>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _PresetPickerSheet(presets: state.recentPresets),
    );
    if (preset == null || !mounted) return;
    _selectPreset(preset);
  }

  void _applyPeriod(_DayPeriod period) {
    setState(() {
      _timestamp = DateTime(
        _timestamp.year,
        _timestamp.month,
        _timestamp.day,
        period.hour,
      );
    });
  }

  void _applyDay(DateTime day) {
    setState(() {
      _timestamp = DateTime(
        day.year,
        day.month,
        day.day,
        _timestamp.hour,
        _timestamp.minute,
      );
    });
  }

  Future<void> _pickTiming() async {
    final now = DateTime.now();
    final initialDate = _timestamp.isAfter(now) ? now : _timestamp;

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: 'Select entry date',
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_timestamp),
      helpText: 'Select entry time',
    );
    if (time == null || !mounted) return;

    var picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (picked.isAfter(now)) picked = now;
    setState(() => _timestamp = picked);
  }

  List<FoodPreset> _suggestions(TrackerState state) {
    final query = _nameController.text.trim().toLowerCase();
    if (query.isEmpty || !_nameFocusNode.hasFocus) return const <FoodPreset>[];

    return state.recentPresets
        .where((preset) {
          if (!preset.name.toLowerCase().contains(query)) return false;
          if (preset.isGroup) return _selectedGroupId != preset.id;
          return !_items.any((item) => item.presetId == preset.id);
        })
        .take(_suggestionLimit)
        .toList(growable: false);
  }

  FoodPreset _presetFromEntry({
    required String name,
    required String category,
    required int calories,
    required num quantity,
    required String? unit,
    required num? protein,
    required num? fats,
    required num? sugar,
  }) {
    if (_items.isEmpty) {
      return FoodPreset(
        id: _uuid.v4(),
        name: name,
        calories: calories,
        defaultCategory: category,
        quantity: quantity,
        unit: unit,
        protein: protein,
        fats: fats,
        sugar: sugar,
      );
    }

    if (_items.length == 1 && _selectedGroupId == null) {
      final item = _items.single;
      return FoodPreset(
        id: _uuid.v4(),
        name: name,
        calories: item.calories,
        defaultCategory: category,
        quantity: item.baseQuantity,
        unit: item.unit,
        protein: item.protein,
        fats: item.fats,
        sugar: item.sugar,
      );
    }

    return FoodPreset.group(
      id: _uuid.v4(),
      name: name,
      defaultCategory: category,
      items: List<FoodGroupItem>.unmodifiable(_items),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final state = context.read<TrackerState>();
    final category = _category;
    if (category == null) return;

    final name = _nameController.text.trim().isEmpty
        ? _autoEntryName(state)
        : _nameController.text.trim();
    if (name.isEmpty) return;

    final calories = _hasItems
        ? _itemsCalories
        : int.tryParse(_caloriesController.text.trim());
    if (calories == null) return;

    final quantity = _hasItems
        ? 1
        : (_parsedQuantity(_quantityController.text) ?? 1);
    final protein = _optionalValue(_proteinController);
    final fats = _optionalValue(_fatsController);
    final sugar = _optionalValue(_sugarController);
    final unit = _hasItems ? null : _unitController.text.trim();
    final comment = _commentController.text.trim();

    setState(() => _saving = true);

    try {
      final entry = FoodEntry(
        id: widget.entry?.id ?? _uuid.v4(),
        foodName: name,
        calories: calories,
        category: category,
        timestamp: _timestamp,
        presetId: _hasItems
            ? _selectedGroupId ??
                  (_items.length == 1 ? _items.single.presetId : null)
            : null,
        items: _hasItems
            ? List<FoodGroupItem>.unmodifiable(_items)
            : const <FoodGroupItem>[],
        protein: protein,
        fats: fats,
        sugar: sugar,
        quantity: quantity,
        unit: unit == null || unit.isEmpty ? null : unit,
        comment: comment.isEmpty ? null : comment,
      );

      if (widget.entry != null) {
        await state.updateFoodEntry(
          entry,
          previousTimestamp: widget.entry!.timestamp,
        );
      } else {
        await state.addFoodEntry(entry);
      }

      if (_saveAsPreset) {
        await state.upsertPreset(
          _presetFromEntry(
            name: name,
            category: category,
            calories: calories,
            quantity: quantity,
            unit: unit == null || unit.isEmpty ? null : unit,
            protein: protein,
            fats: fats,
            sugar: sugar,
          ),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save this entry.\n$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TrackerState>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final categories = <String>{...state.foodCategories};
    if (_category != null) categories.add(_category!);
    if (categories.isEmpty) categories.add('Uncategorized');
    final categoryList = categories.toList()..sort();
    final recentPresets = state.recentPresets
        .take(_recentPresetLimit)
        .toList(growable: false);
    final suggestions = _suggestions(state);

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
                        _isEditing ? 'Edit Food Entry' : 'Add Food Entry',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_isEditing)
                      IconButton(
                        key: const Key('copy-editing-entry-json'),
                        tooltip: 'Copy JSON',
                        onPressed: _saving
                            ? null
                            : () => copyJsonToClipboard(
                                context,
                                widget.entry!.toExportJson(),
                                message:
                                    'Copied ${widget.entry!.foodName} as JSON.',
                              ),
                        icon: const Icon(Icons.copy_rounded),
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
                const SizedBox(height: 8),
                if (recentPresets.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Recent pre-made foods',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        key: const Key('all-presets-button'),
                        onPressed: _saving ? null : _openPresetPicker,
                        icon: const Icon(Icons.search_rounded, size: 18),
                        label: const Text('All'),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: recentPresets.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final preset = recentPresets[index];
                        return ChoiceChip(
                          key: Key('preset-chip-${preset.id}'),
                          label: Text(_presetChipLabel(preset)),
                          avatar: Icon(
                            preset.isGroup
                                ? Icons.lunch_dining_rounded
                                : Icons.bolt_rounded,
                            size: 18,
                          ),
                          selected: _isPresetSelected(preset),
                          onSelected: _saving
                              ? null
                              : (_) => _selectPreset(preset),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Text(
                    'No pre-made foods yet. Save this entry as one below '
                    'so it is ready next time.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_hasItems) ...[
                  _buildItemsCard(theme, colors),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  key: const Key('food-name-field'),
                  controller: _nameController,
                  focusNode: _nameFocusNode,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Food name',
                    hintText: 'e.g. Oatmeal with banana',
                    prefixIcon: Icon(Icons.restaurant_menu_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if ((value == null || value.trim().isEmpty) && !_hasItems) {
                      return 'Enter a food name';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() => _nameEdited = true),
                ),
                if (suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Material(
                    key: const Key('name-suggestions'),
                    color: colors.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: colors.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var index = 0; index < suggestions.length; index++)
                          ListTile(
                            dense: true,
                            leading: Icon(
                              suggestions[index].isGroup
                                  ? Icons.lunch_dining_rounded
                                  : Icons.bolt_rounded,
                              size: 20,
                            ),
                            title: Text(
                              suggestions[index].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _presetDetail(suggestions[index]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.add_rounded, size: 20),
                            onTap: _saving
                                ? null
                                : () => _selectPreset(
                                    suggestions[index],
                                    fromSuggestion: true,
                                  ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('calories-field'),
                        controller: _caloriesController,
                        enabled: !_hasItems,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Calories',
                          suffixText: 'kcal',
                          helperText: _hasItems
                              ? 'Calculated from foods above'
                              : null,
                          prefixIcon: const Icon(
                            Icons.local_fire_department_rounded,
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (_hasItems) return null;
                          final parsed = int.tryParse(value?.trim() ?? '');
                          if (parsed == null) return 'Enter calories';
                          if (parsed < 0) return 'Cannot be negative';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('category-${_category ?? 'none'}'),
                        initialValue: _category,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final category in categoryList)
                            DropdownMenuItem(
                              value: category,
                              child: Text(
                                category,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() => _category = value);
                        },
                        validator: (value) =>
                            value == null ? 'Choose a category' : null,
                      ),
                    ),
                  ],
                ),
                if (!_hasItems) ...[
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const Key('quantity-field'),
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
                            hintText: '1',
                            prefixIcon: Icon(Icons.numbers_rounded),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final parsed = _parsedQuantity(value);
                            if (parsed == null) return 'Enter a quantity';
                            if (parsed <= 0) return 'Must be above zero';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          key: const Key('unit-field'),
                          controller: _unitController,
                          textCapitalization: TextCapitalization.none,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Unit (optional)',
                            hintText: 'g, ml, piece',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Nutrition per entry (optional)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildNutritionField(
                      key: const Key('protein-field'),
                      label: 'Protein',
                      controller: _proteinController,
                    ),
                    const SizedBox(width: 8),
                    _buildNutritionField(
                      key: const Key('fats-field'),
                      label: 'Fats',
                      controller: _fatsController,
                    ),
                    const SizedBox(width: 8),
                    _buildNutritionField(
                      key: const Key('sugar-field'),
                      label: 'Sugar',
                      controller: _sugarController,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('comment-field'),
                  controller: _commentController,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Comment (optional)',
                    hintText: 'e.g. Lunch with friends',
                    prefixIcon: Icon(Icons.notes_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                _buildTimingSection(theme),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _saveAsPreset,
                  onChanged: _saving
                      ? null
                      : (value) =>
                            setState(() => _saveAsPreset = value ?? false),
                  title: const Text('Save as pre-made food'),
                  subtitle: const Text('Add this item to your quick picks'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('save-entry-button'),
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.onPrimary,
                          ),
                        )
                      : Text(_isEditing ? 'Save Changes' : 'Save Entry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isPresetSelected(FoodPreset preset) {
    if (preset.isGroup) return _selectedGroupId == preset.id;
    return _items.any((item) => item.presetId == preset.id);
  }

  String _presetChipLabel(FoodPreset preset) {
    final parts = <String>[preset.name];
    if (preset.isGroup) {
      parts.add('${preset.items.length} items');
    } else if (preset.quantity != 1 ||
        (preset.unit?.trim().isNotEmpty ?? false)) {
      parts.add(formatQuantityWithUnit(preset.quantity, preset.unit));
    }
    parts.add(formatCaloriesWithProtein(preset.calories, preset.protein));
    return parts.join(' · ');
  }

  String _presetDetail(FoodPreset preset) {
    final parts = <String>[];
    if (preset.isGroup) {
      parts.add('${preset.items.length} items');
    } else if (preset.quantity != 1 ||
        (preset.unit?.trim().isNotEmpty ?? false)) {
      parts.add(formatQuantityWithUnit(preset.quantity, preset.unit));
    }
    parts.add(formatCaloriesWithProtein(preset.calories, preset.protein));
    return parts.join(' · ');
  }

  Widget _buildItemsCard(ThemeData theme, ColorScheme colors) {
    final title = _selectedGroupId != null
        ? 'Group contents · ${_items.length} items'
        : 'Foods in this entry · ${_items.length}';

    return Container(
      key: const Key('selected-items-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _selectedGroupId != null
                    ? Icons.lunch_dining_rounded
                    : Icons.restaurant_menu_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                formatCaloriesWithProtein(_itemsCalories, _itemsProtein),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (var index = 0; index < _items.length; index++)
            _EntryItemRow(
              key: ValueKey('entry-item-${_items[index].presetId}-$index'),
              item: _items[index],
              onQuantityChanged: (quantity) =>
                  _updateItemQuantity(index, quantity),
              onRemove: _saving ? null : () => _removeItem(index),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('add-more-foods-button'),
              onPressed: _saving ? null : _openPresetPicker,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add more food'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimingSection(ThemeData theme) {
    final colors = theme.colorScheme;
    final selectedPeriod = _DayPeriod.forHour(_timestamp.hour);
    final today = dateOnly(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Timing',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final period in _DayPeriod.values)
              ChoiceChip(
                key: Key('timing-${period.name}-chip'),
                label: Text(period.label),
                selected: selectedPeriod == period,
                onSelected: _saving ? null : (_) => _applyPeriod(period),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Day',
          style: theme.textTheme.labelLarge?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const Key('timing-today-chip'),
              label: const Text('Today'),
              selected: isSameDate(_timestamp, today),
              onSelected: _saving ? null : (_) => _applyDay(today),
            ),
            ChoiceChip(
              key: const Key('timing-yesterday-chip'),
              label: const Text('Yesterday'),
              selected: isSameDate(_timestamp, yesterday),
              onSelected: _saving ? null : (_) => _applyDay(yesterday),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Selected date & time',
            prefixIcon: const Icon(Icons.schedule_rounded),
            suffixIcon: IconButton(
              key: const Key('custom-timing-button'),
              tooltip: 'Set exact date and time',
              onPressed: _saving ? null : _pickTiming,
              icon: const Icon(Icons.edit_calendar_rounded),
            ),
            border: const OutlineInputBorder(),
          ),
          child: Text(
            formatDateTime(_timestamp),
            key: const Key('selected-timing-text'),
          ),
        ),
      ],
    );
  }

  Widget _buildNutritionField({
    required Key key,
    required String label,
    required TextEditingController controller,
  }) {
    return Expanded(
      child: TextFormField(
        key: key,
        controller: controller,
        enabled: !_hasItems,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
        ],
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'g',
          border: const OutlineInputBorder(),
        ),
        validator: optionalNumberValidator,
      ),
    );
  }
}

/// One editable food row inside a multi-item entry.
class _EntryItemRow extends StatefulWidget {
  const _EntryItemRow({
    super.key,
    required this.item,
    required this.onQuantityChanged,
    this.onRemove,
  });

  final FoodGroupItem item;
  final ValueChanged<num> onQuantityChanged;
  final VoidCallback? onRemove;

  @override
  State<_EntryItemRow> createState() => _EntryItemRowState();
}

class _EntryItemRowState extends State<_EntryItemRow> {
  late final TextEditingController _quantityController;
  final FocusNode _quantityFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: formatQuantity(widget.item.quantity),
    );
  }

  @override
  void didUpdateWidget(covariant _EntryItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_quantityFocusNode.hasFocus &&
        widget.item.quantity != oldWidget.item.quantity) {
      _quantityController.text = formatQuantity(widget.item.quantity);
    }
  }

  @override
  void dispose() {
    _quantityFocusNode.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _onQuantityChanged(String value) {
    final parsed = num.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return;
    widget.onQuantityChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final item = widget.item;
    final unitLabel = item.unit?.trim();
    final suffix = unitLabel == null || unitLabel.isEmpty ? null : unitLabel;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatCaloriesWithProtein(
                    item.totalCalories,
                    item.totalProtein,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 124,
            child: TextFormField(
              controller: _quantityController,
              focusNode: _quantityFocusNode,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Weight / qty',
                suffixText: suffix,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                final parsed = num.tryParse(value?.trim() ?? '');
                if (parsed == null) return 'Required';
                if (parsed <= 0) return 'Above 0';
                return null;
              },
              onChanged: _onQuantityChanged,
            ),
          ),
          IconButton(
            tooltip: 'Remove ${item.name}',
            onPressed: widget.onRemove,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

/// Searchable picker used by "All" and "Add more food".
class _PresetPickerSheet extends StatefulWidget {
  const _PresetPickerSheet({required this.presets});

  final List<FoodPreset> presets;

  @override
  State<_PresetPickerSheet> createState() => _PresetPickerSheetState();
}

class _PresetPickerSheetState extends State<_PresetPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final query = _query.trim().toLowerCase();
    final matches = widget.presets
        .where(
          (preset) =>
              query.isEmpty || preset.name.toLowerCase().contains(query),
        )
        .toList(growable: false);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: TextField(
                key: const Key('preset-picker-search'),
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Search pre-made foods',
                  prefixIcon: Icon(Icons.search_rounded),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(
                        'No matching pre-made foods',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final preset = matches[index];
                        return ListTile(
                          leading: Icon(
                            preset.isGroup
                                ? Icons.lunch_dining_rounded
                                : Icons.bolt_rounded,
                          ),
                          title: Text(preset.name),
                          subtitle: Text(_presetDetail(preset)),
                          trailing: const Icon(Icons.add_rounded),
                          onTap: () => Navigator.of(context).pop(preset),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _presetDetail(FoodPreset preset) {
    final parts = <String>[];
    if (preset.isGroup) {
      parts.add('${preset.items.length} items');
    } else if (preset.quantity != 1 ||
        (preset.unit?.trim().isNotEmpty ?? false)) {
      parts.add(formatQuantityWithUnit(preset.quantity, preset.unit));
    }
    parts.add(formatCaloriesWithProtein(preset.calories, preset.protein));
    return parts.join(' · ');
  }
}
