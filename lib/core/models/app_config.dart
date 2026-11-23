/// Contents of `config.json`.
///
/// This object is loaded once at startup, kept in memory by [TrackerState] and
/// written back asynchronously whenever a setting changes.
class AppConfig {
  AppConfig({
    required this.vaultVersion,
    required this.dailyCalorieGoal,
    required List<String> junkFoodCategories,
    required List<String> foodCategories,
    required List<String> enabledModules,
  }) : junkFoodCategories = List.unmodifiable(junkFoodCategories),
       foodCategories = List.unmodifiable(foodCategories),
       enabledModules = List.unmodifiable(enabledModules);

  factory AppConfig.defaults() {
    return AppConfig(
      vaultVersion: currentVaultVersion,
      dailyCalorieGoal: 2200,
      junkFoodCategories: const ['Junk', 'Fast Food', 'Sweets'],
      foodCategories: const [
        'Healthy',
        'Junk',
        'Protein',
        'Snacks',
        'Beverages',
      ],
      enabledModules: const ['food'],
    );
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final defaults = AppConfig.defaults();
    final calorieGoal = json['dailyCalorieGoal'];
    final vaultVersion = json['vaultVersion'];

    return AppConfig(
      vaultVersion: vaultVersion is int ? vaultVersion : defaults.vaultVersion,
      dailyCalorieGoal: calorieGoal is int && calorieGoal > 0
          ? calorieGoal
          : defaults.dailyCalorieGoal,
      junkFoodCategories:
          _stringList(json['junkFoodCategories']) ??
          defaults.junkFoodCategories,
      foodCategories:
          _stringList(json['foodCategories']) ?? defaults.foodCategories,
      enabledModules:
          _stringList(json['enabledModules']) ?? defaults.enabledModules,
    );
  }

  static const int currentVaultVersion = 1;

  final int vaultVersion;
  final int dailyCalorieGoal;
  final List<String> junkFoodCategories;
  final List<String> foodCategories;
  final List<String> enabledModules;

  bool isJunkCategory(String category) => junkFoodCategories.contains(category);

  AppConfig copyWith({
    int? vaultVersion,
    int? dailyCalorieGoal,
    List<String>? junkFoodCategories,
    List<String>? foodCategories,
    List<String>? enabledModules,
  }) {
    return AppConfig(
      vaultVersion: vaultVersion ?? this.vaultVersion,
      dailyCalorieGoal: dailyCalorieGoal ?? this.dailyCalorieGoal,
      junkFoodCategories: junkFoodCategories ?? this.junkFoodCategories,
      foodCategories: foodCategories ?? this.foodCategories,
      enabledModules: enabledModules ?? this.enabledModules,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vaultVersion': vaultVersion,
      'dailyCalorieGoal': dailyCalorieGoal,
      'junkFoodCategories': junkFoodCategories,
      'foodCategories': foodCategories,
      'enabledModules': enabledModules,
    };
  }

  static List<String>? _stringList(Object? value) {
    if (value is! List) return null;
    return value.whereType<String>().toList(growable: false);
  }
}
