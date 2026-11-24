import 'package:junk_food_tracker/core/models/tracker_entry.dart';
import 'package:junk_food_tracker/features/food/models/food_preset.dart';

/// A single logged food item.
///
/// [protein], [fats] and [sugar] are optional per-entry nutrition values;
/// [calories] is the entry's total. [quantity] is the number of servings
/// logged and [unit] is an optional label for what the quantity means
/// (for example "g" or "ml"). [comment] is an optional free-form note.
///
/// An entry can also be a meal built from several pre-made foods. Those
/// foods are stored in [items] with their own weights and calories. For such
/// entries [foodName] is the meal name and [calories] is the sum of [items].
class FoodEntry implements TrackerEntry {
  const FoodEntry({
    required this.id,
    required this.foodName,
    required this.calories,
    required this.category,
    required this.timestamp,
    this.presetId,
    this.items = const <FoodGroupItem>[],
    this.protein,
    this.fats,
    this.sugar,
    this.quantity = 1,
    this.unit,
    this.comment,
  }) : assert(calories >= 0, 'Calories cannot be negative.'),
       assert(quantity >= 0, 'Quantity cannot be negative.');

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

    final protein = json['protein'];
    final fats = json['fats'];
    final sugar = json['sugar'];
    final quantity = json['quantity'];
    final unit = json['unit'];
    final comment = json['comment'];
    final presetId = json['presetId'];
    final rawItems = json['items'];

    if (presetId != null && presetId is! String) {
      throw const FormatException('Invalid food entry preset id.');
    }
    if (protein != null && protein is! num) {
      throw const FormatException('Invalid food entry protein field.');
    }
    if (fats != null && fats is! num) {
      throw const FormatException('Invalid food entry fats field.');
    }
    if (sugar != null && sugar is! num) {
      throw const FormatException('Invalid food entry sugar field.');
    }
    if (quantity != null && quantity is! num) {
      throw const FormatException('Invalid food entry quantity field.');
    }
    if (unit != null && unit is! String) {
      throw const FormatException('Invalid food entry unit field.');
    }
    if (comment != null && comment is! String) {
      throw const FormatException('Invalid food entry comment field.');
    }

    final parsedQuantity = quantity as num? ?? 1;
    if (parsedQuantity < 0) {
      throw const FormatException('Invalid food entry quantity.');
    }

    final items = <FoodGroupItem>[];
    if (rawItems is List) {
      for (final rawItem in rawItems) {
        if (rawItem is! Map) continue;
        try {
          items.add(FoodGroupItem.fromJson(Map<String, dynamic>.from(rawItem)));
        } on FormatException {
          // Keep the entry usable if one item is malformed.
        }
      }
    }

    return FoodEntry(
      id: id,
      foodName: foodName,
      calories: calories.toInt(),
      category: category,
      timestamp: parsedTimestamp.toLocal(),
      presetId: presetId as String?,
      items: List.unmodifiable(items),
      protein: protein as num?,
      fats: fats as num?,
      sugar: sugar as num?,
      quantity: parsedQuantity,
      unit: unit as String?,
      comment: comment as String?,
    );
  }

  @override
  final String id;

  final String foodName;
  final int calories;
  final String category;

  /// The pre-made food this entry came from, when it was a single selection.
  final String? presetId;

  /// Pre-made foods used to build this entry, in display order.
  final List<FoodGroupItem> items;

  bool get hasItems => items.isNotEmpty;

  /// Total protein in the entry, when known.
  final num? protein;

  /// Protein for the whole entry, falling back to the sum of [items].
  ///
  /// Entries saved before multi-item meals stored the total in [protein];
  /// those keep working unchanged.
  num? get totalProtein {
    if (protein != null) return protein;
    if (items.isEmpty) return null;

    var found = false;
    num total = 0;
    for (final item in items) {
      final value = item.totalProtein;
      if (value != null) {
        found = true;
        total += value;
      }
    }
    return found ? total : null;
  }

  /// Total fats in the entry, when known.
  final num? fats;

  /// Total sugar in the entry, when known.
  final num? sugar;

  /// Number of servings logged for this entry.
  final num quantity;

  /// Optional display label for the quantity, e.g. "g" or "ml".
  final String? unit;

  /// Optional free-form note attached to this entry.
  final String? comment;

  @override
  final DateTime timestamp;

  FoodEntry copyWith({
    String? id,
    String? foodName,
    int? calories,
    String? category,
    DateTime? timestamp,
    String? presetId,
    List<FoodGroupItem>? items,
    num? protein,
    num? fats,
    num? sugar,
    num? quantity,
    String? unit,
    String? comment,
  }) {
    return FoodEntry(
      id: id ?? this.id,
      foodName: foodName ?? this.foodName,
      calories: calories ?? this.calories,
      category: category ?? this.category,
      timestamp: timestamp ?? this.timestamp,
      presetId: presetId ?? this.presetId,
      items: items ?? this.items,
      protein: protein ?? this.protein,
      fats: fats ?? this.fats,
      sugar: sugar ?? this.sugar,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      comment: comment ?? this.comment,
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
      if (presetId != null) 'presetId': presetId,
      if (items.isNotEmpty) 'items': [for (final item in items) item.toJson()],
      if (protein != null) 'protein': protein,
      if (fats != null) 'fats': fats,
      if (sugar != null) 'sugar': sugar,
      'quantity': quantity,
      if (unit != null) 'unit': unit,
      if (comment != null) 'comment': comment,
    };
  }
}
