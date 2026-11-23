/// A reusable food item stored in `food_presets.json`.
class FoodPreset {
  const FoodPreset({
    required this.id,
    required this.name,
    required this.calories,
    required this.defaultCategory,
  }) : assert(calories >= 0, 'Calories cannot be negative.');

  factory FoodPreset.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final calories = json['calories'];
    final category = json['defaultCategory'];

    if (id is! String ||
        name is! String ||
        calories is! num ||
        category is! String) {
      throw const FormatException('Invalid food preset fields.');
    }

    return FoodPreset(
      id: id,
      name: name,
      calories: calories.toInt(),
      defaultCategory: category,
    );
  }

  final String id;
  final String name;
  final int calories;
  final String defaultCategory;

  FoodPreset copyWith({
    String? id,
    String? name,
    int? calories,
    String? defaultCategory,
  }) {
    return FoodPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      calories: calories ?? this.calories,
      defaultCategory: defaultCategory ?? this.defaultCategory,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'calories': calories,
      'defaultCategory': defaultCategory,
    };
  }
}
