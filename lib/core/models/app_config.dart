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
    this.dailyReminderEnabled = false,
    this.dailyReminderHour = defaultReminderHour,
    this.dailyReminderMinute = defaultReminderMinute,
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
    final reminderEnabled = json['dailyReminderEnabled'];
    final reminderHour = json['dailyReminderHour'];
    final reminderMinute = json['dailyReminderMinute'];

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
      dailyReminderEnabled: reminderEnabled is bool
          ? reminderEnabled
          : defaults.dailyReminderEnabled,
      dailyReminderHour: reminderHour is int && _isValidHour(reminderHour)
          ? reminderHour
          : defaults.dailyReminderHour,
      dailyReminderMinute:
          reminderMinute is int && _isValidMinute(reminderMinute)
          ? reminderMinute
          : defaults.dailyReminderMinute,
    );
  }

  static const int currentVaultVersion = 1;
  static const int defaultReminderHour = 21;
  static const int defaultReminderMinute = 0;

  final int vaultVersion;
  final int dailyCalorieGoal;
  final List<String> junkFoodCategories;
  final List<String> foodCategories;
  final List<String> enabledModules;

  /// Whether the app posts a daily notification with the day's calorie total.
  final bool dailyReminderEnabled;

  /// Hour of the daily reminder (0-23).
  final int dailyReminderHour;

  /// Minute of the daily reminder (0-59).
  final int dailyReminderMinute;

  bool isJunkCategory(String category) => junkFoodCategories.contains(category);

  AppConfig copyWith({
    int? vaultVersion,
    int? dailyCalorieGoal,
    List<String>? junkFoodCategories,
    List<String>? foodCategories,
    List<String>? enabledModules,
    bool? dailyReminderEnabled,
    int? dailyReminderHour,
    int? dailyReminderMinute,
  }) {
    return AppConfig(
      vaultVersion: vaultVersion ?? this.vaultVersion,
      dailyCalorieGoal: dailyCalorieGoal ?? this.dailyCalorieGoal,
      junkFoodCategories: junkFoodCategories ?? this.junkFoodCategories,
      foodCategories: foodCategories ?? this.foodCategories,
      enabledModules: enabledModules ?? this.enabledModules,
      dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
      dailyReminderHour: dailyReminderHour ?? this.dailyReminderHour,
      dailyReminderMinute: dailyReminderMinute ?? this.dailyReminderMinute,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vaultVersion': vaultVersion,
      'dailyCalorieGoal': dailyCalorieGoal,
      'junkFoodCategories': junkFoodCategories,
      'foodCategories': foodCategories,
      'enabledModules': enabledModules,
      'dailyReminderEnabled': dailyReminderEnabled,
      'dailyReminderHour': dailyReminderHour,
      'dailyReminderMinute': dailyReminderMinute,
    };
  }

  static bool _isValidHour(int hour) => hour >= 0 && hour <= 23;

  static bool _isValidMinute(int minute) => minute >= 0 && minute <= 59;

  static List<String>? _stringList(Object? value) {
    if (value is! List) return null;
    return value.whereType<String>().toList(growable: false);
  }
}
