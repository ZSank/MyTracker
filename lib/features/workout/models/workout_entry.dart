import 'package:junk_food_tracker/core/models/tracker_entry.dart';

/// One extra activity used to offset the day's food calories.
///
/// Burned calories are stored as a positive number; the dashboard subtracts
/// them only when it computes the net total. This keeps the stored value
/// unambiguous and avoids negative numbers leaking into food-only metrics.
class WorkoutEntry implements TrackerEntry {
  const WorkoutEntry({
    required this.id,
    required this.name,
    required this.caloriesBurned,
    required this.timestamp,
  }) : assert(caloriesBurned > 0, 'Burned calories must be positive.');

  factory WorkoutEntry.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final caloriesBurned = json['caloriesBurned'];
    final timestamp = json['timestamp'];

    if (id is! String ||
        name is! String ||
        caloriesBurned is! num ||
        timestamp is! String) {
      throw const FormatException('Invalid workout entry fields.');
    }

    if (caloriesBurned <= 0) {
      throw const FormatException('Burned calories must be positive.');
    }

    final parsedTimestamp = DateTime.tryParse(timestamp);
    if (parsedTimestamp == null) {
      throw FormatException('Invalid workout timestamp: $timestamp');
    }

    return WorkoutEntry(
      id: id,
      name: name,
      caloriesBurned: caloriesBurned.round(),
      timestamp: parsedTimestamp,
    );
  }

  @override
  final String id;

  final String name;

  /// Positive calories burned by this activity.
  final int caloriesBurned;

  @override
  final DateTime timestamp;

  WorkoutEntry copyWith({
    String? name,
    int? caloriesBurned,
    DateTime? timestamp,
  }) {
    return WorkoutEntry(
      id: id,
      name: name ?? this.name,
      caloriesBurned: caloriesBurned ?? this.caloriesBurned,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'caloriesBurned': caloriesBurned,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
