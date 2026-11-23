/// Whether a pre-made food is a single item or a group of other items.
enum FoodPresetType { simple, group }

/// One line inside a grouped pre-made food.
///
/// The nutrition values are snapshots of the source preset's per-serving
/// values, so the group keeps working if that preset is later edited or
/// deleted. Totals are multiplied by [quantity].
class FoodGroupItem {
  const FoodGroupItem({
    required this.presetId,
    required this.name,
    required this.quantity,
    required this.calories,
    this.unit,
    this.protein,
    this.fats,
    this.sugar,
  }) : assert(quantity > 0, 'Quantity must be above zero.'),
       assert(calories >= 0, 'Calories cannot be negative.');

  factory FoodGroupItem.fromJson(Map<String, dynamic> json) {
    final presetId = json['presetId'];
    final name = json['name'];
    final quantity = json['quantity'];
    final calories = json['calories'];
    final unit = json['unit'];
    final protein = json['protein'];
    final fats = json['fats'];
    final sugar = json['sugar'];

    if (presetId is! String ||
        name is! String ||
        quantity is! num ||
        calories is! num) {
      throw const FormatException('Invalid food group item fields.');
    }
    if (quantity <= 0 || calories < 0) {
      throw const FormatException('Invalid food group item values.');
    }
    if (unit != null && unit is! String) {
      throw const FormatException('Invalid food group item unit.');
    }
    if (protein != null && protein is! num) {
      throw const FormatException('Invalid food group item protein.');
    }
    if (fats != null && fats is! num) {
      throw const FormatException('Invalid food group item fats.');
    }
    if (sugar != null && sugar is! num) {
      throw const FormatException('Invalid food group item sugar.');
    }

    return FoodGroupItem(
      presetId: presetId,
      name: name,
      quantity: quantity,
      unit: unit as String?,
      calories: calories.toInt(),
      protein: protein as num?,
      fats: fats as num?,
      sugar: sugar as num?,
    );
  }

  final String presetId;
  final String name;

  /// How many servings of the source preset are in the group.
  final num quantity;

  /// Optional display label for the quantity, e.g. "g" or "ml".
  final String? unit;

  /// Calories in one serving of the source preset.
  final int calories;

  final num? protein;
  final num? fats;
  final num? sugar;

  int get totalCalories => (calories * quantity).round();

  num? get totalProtein => protein == null ? null : protein! * quantity;

  num? get totalFats => fats == null ? null : fats! * quantity;

  num? get totalSugar => sugar == null ? null : sugar! * quantity;

  Map<String, dynamic> toJson() {
    return {
      'presetId': presetId,
      'name': name,
      'quantity': quantity,
      if (unit != null) 'unit': unit,
      'calories': calories,
      if (protein != null) 'protein': protein,
      if (fats != null) 'fats': fats,
      if (sugar != null) 'sugar': sugar,
    };
  }
}

/// A reusable food item stored in `food_presets.json`.
///
/// A [FoodPresetType.simple] preset stores its own per-serving nutrition. A
/// [FoodPresetType.group] preset is built from other presets and exposes the
/// sum of its [items] through the same getters, so the rest of the app can
/// treat both kinds identically.
class FoodPreset {
  const FoodPreset({
    required this.id,
    required this.name,
    required this.defaultCategory,
    this.type = FoodPresetType.simple,
    int calories = 0,
    num? protein,
    num? fats,
    num? sugar,
    this.items = const <FoodGroupItem>[],
  }) : _storedCalories = calories,
       _storedProtein = protein,
       _storedFats = fats,
       _storedSugar = sugar;

  /// Builds a grouped pre-made food from the given [items].
  const FoodPreset.group({
    required this.id,
    required this.name,
    required this.defaultCategory,
    required this.items,
  }) : type = FoodPresetType.group,
       _storedCalories = 0,
       _storedProtein = null,
       _storedFats = null,
       _storedSugar = null;

  factory FoodPreset.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final category = json['defaultCategory'];
    final rawType = json['type'];

    if (id is! String || name is! String || category is! String) {
      throw const FormatException('Invalid food preset fields.');
    }

    final type = switch (rawType) {
      null || 'simple' => FoodPresetType.simple,
      'group' => FoodPresetType.group,
      _ => throw FormatException('Invalid food preset type: $rawType'),
    };

    if (type == FoodPresetType.group) {
      final rawItems = json['items'];
      if (rawItems is! List) {
        throw const FormatException('Invalid food group items.');
      }

      final items = <FoodGroupItem>[];
      for (final rawItem in rawItems) {
        if (rawItem is! Map) continue;
        try {
          items.add(FoodGroupItem.fromJson(Map<String, dynamic>.from(rawItem)));
        } on FormatException {
          // Keep the rest of the group usable if one item is malformed.
        }
      }

      return FoodPreset.group(
        id: id,
        name: name,
        defaultCategory: category,
        items: List.unmodifiable(items),
      );
    }

    final calories = json['calories'];
    final protein = json['protein'];
    final fats = json['fats'];
    final sugar = json['sugar'];

    if (calories is! num) {
      throw const FormatException('Invalid food preset calories.');
    }
    if (protein != null && protein is! num) {
      throw const FormatException('Invalid food preset protein.');
    }
    if (fats != null && fats is! num) {
      throw const FormatException('Invalid food preset fats.');
    }
    if (sugar != null && sugar is! num) {
      throw const FormatException('Invalid food preset sugar.');
    }

    return FoodPreset(
      id: id,
      name: name,
      calories: calories.toInt(),
      defaultCategory: category,
      protein: protein as num?,
      fats: fats as num?,
      sugar: sugar as num?,
    );
  }

  final String id;
  final String name;
  final String defaultCategory;
  final FoodPresetType type;

  /// Present only for grouped presets.
  final List<FoodGroupItem> items;

  final int _storedCalories;
  final num? _storedProtein;
  final num? _storedFats;
  final num? _storedSugar;

  bool get isGroup => type == FoodPresetType.group;

  /// Per-serving calories (or the whole group's calories for groups).
  int get calories => isGroup
      ? items.fold<int>(0, (total, item) => total + item.totalCalories)
      : _storedCalories;

  /// Per-serving protein (or the whole group's protein for groups).
  num? get protein =>
      isGroup ? _sumOptional((item) => item.totalProtein) : _storedProtein;

  /// Per-serving fats (or the whole group's fats for groups).
  num? get fats =>
      isGroup ? _sumOptional((item) => item.totalFats) : _storedFats;

  /// Per-serving sugar (or the whole group's sugar for groups).
  num? get sugar =>
      isGroup ? _sumOptional((item) => item.totalSugar) : _storedSugar;

  num? _sumOptional(num? Function(FoodGroupItem item) read) {
    var found = false;
    num total = 0;
    for (final item in items) {
      final value = read(item);
      if (value != null) {
        found = true;
        total += value;
      }
    }
    return found ? total : null;
  }

  FoodPreset copyWith({
    String? id,
    String? name,
    int? calories,
    String? defaultCategory,
    FoodPresetType? type,
    num? protein,
    num? fats,
    num? sugar,
    List<FoodGroupItem>? items,
  }) {
    return FoodPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      calories: calories ?? _storedCalories,
      defaultCategory: defaultCategory ?? this.defaultCategory,
      type: type ?? this.type,
      protein: protein ?? _storedProtein,
      fats: fats ?? _storedFats,
      sugar: sugar ?? _storedSugar,
      items: items ?? this.items,
    );
  }

  Map<String, dynamic> toJson() {
    if (isGroup) {
      return {
        'id': id,
        'name': name,
        'defaultCategory': defaultCategory,
        'type': 'group',
        'items': [for (final item in items) item.toJson()],
      };
    }

    return {
      'id': id,
      'name': name,
      'calories': _storedCalories,
      'defaultCategory': defaultCategory,
      'type': 'simple',
      if (_storedProtein != null) 'protein': _storedProtein,
      if (_storedFats != null) 'fats': _storedFats,
      if (_storedSugar != null) 'sugar': _storedSugar,
    };
  }
}
