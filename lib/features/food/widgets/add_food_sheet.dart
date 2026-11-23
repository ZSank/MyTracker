import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:junk_food_tracker/core/state/tracker_state.dart';
import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';
import 'package:junk_food_tracker/shared/utils/formatters.dart';
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

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
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
  FoodPreset? _selectedPreset;
  bool _saveAsPreset = false;
  bool _saving = false;

  bool get _isEditing => widget.entry != null;

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
  }

  @override
  void dispose() {
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

  void _fillNutrition(FoodPreset preset, num quantity) {
    _caloriesController.text = (preset.calories * quantity).round().toString();
    _proteinController.text = preset.protein == null
        ? ''
        : formatQuantity(preset.protein! * quantity);
    _fatsController.text = preset.fats == null
        ? ''
        : formatQuantity(preset.fats! * quantity);
    _sugarController.text = preset.sugar == null
        ? ''
        : formatQuantity(preset.sugar! * quantity);
  }

  void _applyPreset(FoodPreset preset) {
    var quantity = _parsedQuantity(_quantityController.text) ?? 1;
    if (quantity <= 0) quantity = 1;

    setState(() {
      _selectedPreset = preset;
      _nameController.text = preset.name;
      _category = preset.defaultCategory;
      _saveAsPreset = false;
      _quantityController.text = formatQuantity(quantity);
      _fillNutrition(preset, quantity);
    });
  }

  void _onQuantityChanged(String value) {
    final preset = _selectedPreset;
    if (preset == null) return;

    final quantity = _parsedQuantity(value);
    if (quantity == null || quantity <= 0) return;
    _fillNutrition(preset, quantity);
  }

  void _clearPresetSelection() {
    if (_selectedPreset != null) {
      setState(() => _selectedPreset = null);
    }
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final state = context.read<TrackerState>();
    final category = _category;
    final calories = int.tryParse(_caloriesController.text.trim());
    final quantity = _parsedQuantity(_quantityController.text);
    if (category == null || calories == null || quantity == null) return;

    final protein = _optionalValue(_proteinController);
    final fats = _optionalValue(_fatsController);
    final sugar = _optionalValue(_sugarController);
    final unit = _unitController.text.trim();
    final comment = _commentController.text.trim();

    setState(() => _saving = true);

    try {
      final name = _nameController.text.trim();
      final entry = FoodEntry(
        id: widget.entry?.id ?? _uuid.v4(),
        foodName: name,
        calories: calories,
        category: category,
        timestamp: _timestamp,
        protein: protein,
        fats: fats,
        sugar: sugar,
        quantity: quantity,
        unit: unit.isEmpty ? null : unit,
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
          FoodPreset(
            id: _uuid.v4(),
            name: name,
            calories: (calories / quantity).round(),
            defaultCategory: category,
            protein: protein == null ? null : protein / quantity,
            fats: fats == null ? null : fats / quantity,
            sugar: sugar == null ? null : sugar / quantity,
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
    final selectedPreset = _selectedPreset;

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
                if (state.presets.isNotEmpty) ...[
                  Text(
                    'Pre-made foods',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: state.presets.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final preset = state.presets[index];
                        return ChoiceChip(
                          label: Text(
                            '${preset.name} · '
                            '${formatNumber(preset.calories)} kcal',
                          ),
                          avatar: Icon(
                            preset.isGroup
                                ? Icons.lunch_dining_rounded
                                : Icons.bolt_rounded,
                            size: 18,
                          ),
                          selected: selectedPreset?.id == preset.id,
                          onSelected: (_) => _applyPreset(preset),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ] else ...[
                  Text(
                    'No pre-made foods yet. Save this entry as one below '
                    'so it is ready next time.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                if (selectedPreset != null && selectedPreset.isGroup) ...[
                  _GroupContentsCard(preset: selectedPreset),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  key: const Key('food-name-field'),
                  controller: _nameController,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Food name',
                    hintText: 'e.g. Oatmeal with banana',
                    prefixIcon: Icon(Icons.restaurant_menu_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter a food name';
                    }
                    return null;
                  },
                  onChanged: (_) => _clearPresetSelection(),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('calories-field'),
                        controller: _caloriesController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Calories',
                          suffixText: 'kcal',
                          prefixIcon: Icon(Icons.local_fire_department_rounded),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final parsed = int.tryParse(value?.trim() ?? '');
                          if (parsed == null) return 'Enter calories';
                          if (parsed < 0) return 'Cannot be negative';
                          return null;
                        },
                        onChanged: (_) => _clearPresetSelection(),
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
                          setState(() {
                            _category = value;
                            _selectedPreset = null;
                          });
                        },
                        validator: (value) =>
                            value == null ? 'Choose a category' : null,
                      ),
                    ),
                  ],
                ),
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
                          labelText: 'Quantity',
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
                        onChanged: _onQuantityChanged,
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
        onChanged: (_) => _clearPresetSelection(),
      ),
    );
  }
}

class _GroupContentsCard extends StatelessWidget {
  const _GroupContentsCard({required this.preset});

  final FoodPreset preset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      key: ValueKey('group-contents-${preset.id}'),
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
                Icons.lunch_dining_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Group contents · ${preset.items.length} items',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final item in preset.items)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${formatQuantityWithUnit(item.quantity, item.unit)}'
                      ' · ${item.name}',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${formatNumber(item.totalCalories)} kcal',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
