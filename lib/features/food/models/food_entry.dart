import 'package:junk_food_tracker/core/models/tracker_entry.dart';

/// A single logged food item.
class FoodEntry implements TrackerEntry {
  const FoodEntry({
    required this.id,
    required this.foodName,
    required this.calories,
    required this.category,
    required this.timestamp,
  }) : assert(calories >= 0, 'Calories cannot be negative.');

  factory FoodEntry.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final foodName = json['foodName'];
    final calories = json['calories'];
    final category = json['category'];
    final timestamp = json['timestamp'];

    if (id is! String ||
        foodName is! String ||
        calories is! num ||
        category is! String ||
        timestamp is! String) {
      throw const FormatException('Invalid food entry fields.');
    }

    final parsedTimestamp = DateTime.tryParse(timestamp);
    if (parsedTimestamp == null) {
      throw FormatException('Invalid food entry timestamp: $timestamp');
    }

    return FoodEntry(
      id: id,
      foodName: foodName,
      calories: calories.toInt(),
      category: category,
      timestamp: parsedTimestamp.toLocal(),
    );
  }

  @override
  final String id;

  final String foodName;
  final int calories;
  final String category;

  @override
  final DateTime timestamp;

  FoodEntry copyWith({
    String? id,
    String? foodName,
    int? calories,
    String? category,
    DateTime? timestamp,
  }) {
    return FoodEntry(
      id: id ?? this.id,
      foodName: foodName ?? this.foodName,
      calories: calories ?? this.calories,
      category: category ?? this.category,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'foodName': foodName,
      'calories': calories,
      'category': category,
      'timestamp': timestamp.toUtc().toIso8601String(),
    };
  }
}
