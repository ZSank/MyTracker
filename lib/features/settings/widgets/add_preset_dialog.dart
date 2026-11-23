import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';
import 'package:junk_food_tracker/shared/utils/formatters.dart';
import 'package:uuid/uuid.dart';

class AddPresetDialog extends StatefulWidget {
  const AddPresetDialog({super.key, required this.categories, this.preset});

  final List<String> categories;

  /// When provided, the dialog edits this pre-made food instead of adding one.
  final FoodPreset? preset;

  bool get isEditing => preset != null;

  @override
  State<AddPresetDialog> createState() => _AddPresetDialogState();
}

class _AddPresetDialogState extends State<AddPresetDialog> {
  static const Uuid _uuid = Uuid();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _caloriesController = TextEditingController();
  final TextEditingController _proteinController = TextEditingController();
  final TextEditingController _fatsController = TextEditingController();
  final TextEditingController _sugarController = TextEditingController();
  late String _category;

  @override
  void initState() {
    super.initState();
    final preset = widget.preset;
    _category =
        preset?.defaultCategory ??
        (widget.categories.isNotEmpty
            ? widget.categories.first
            : 'Uncategorized');
    if (preset == null) return;

    _nameController.text = preset.name;
    _caloriesController.text = preset.calories.toString();
    _proteinController.text = _formatOptionalValue(preset.protein);
    _fatsController.text = _formatOptionalValue(preset.fats);
    _sugarController.text = _formatOptionalValue(preset.sugar);
  }

  static String _formatOptionalValue(num? value) {
    if (value == null) return '';
    return value == value.roundToDouble() ? value.toInt().toString() : '$value';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _fatsController.dispose();
    _sugarController.dispose();
    super.dispose();
  }

  num? _optionalValue(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return num.tryParse(text);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final calories = int.tryParse(_caloriesController.text.trim());
    if (calories == null) return;

    Navigator.of(context).pop(
      FoodPreset(
        id: widget.preset?.id ?? _uuid.v4(),
        name: _nameController.text.trim(),
        calories: calories,
        defaultCategory: _category,
        protein: _optionalValue(_proteinController),
        fats: _optionalValue(_fatsController),
        sugar: _optionalValue(_sugarController),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String>{...widget.categories, _category}.toList()
      ..sort();

    return AlertDialog(
      title: Text(
        widget.isEditing ? 'Edit Pre-made Food' : 'New Pre-made Food',
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('preset-name-field'),
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Food name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter a food name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('preset-calories-field'),
                controller: _caloriesController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Calories',
                  suffixText: 'kcal',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  if (parsed == null) return 'Enter calories';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildNutritionField(
                    key: const Key('preset-protein-field'),
                    label: 'Protein',
                    controller: _proteinController,
                  ),
                  const SizedBox(width: 8),
                  _buildNutritionField(
                    key: const Key('preset-fats-field'),
                    label: 'Fats',
                    controller: _fatsController,
                  ),
                  const SizedBox(width: 8),
                  _buildNutritionField(
                    key: const Key('preset-sugar-field'),
                    label: 'Sugar',
                    controller: _sugarController,
                  ),
                ],
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('add-preset-confirm'),
          onPressed: _submit,
          child: Text(widget.isEditing ? 'Save' : 'Add'),
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
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        validator: optionalNumberValidator,
      ),
    );
  }
}
