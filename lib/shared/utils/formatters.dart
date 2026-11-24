import 'package:intl/intl.dart';
import 'package:junk_food_tracker/features/food/models/food_entry.dart';

final NumberFormat _numberFormat = NumberFormat.decimalPattern();
final NumberFormat _quantityFormat = NumberFormat('#,##0.###');
final DateFormat _timeFormat = DateFormat.jm();
final DateFormat _dateTimeFormat = DateFormat.yMMMd().add_jm();
final DateFormat _shortDateTimeFormat = DateFormat('MMM d, h:mm a');
final DateFormat _dayHeaderFormat = DateFormat('EEEE, MMM d');

String formatNumber(int value) => _numberFormat.format(value);

/// Formats a quantity without unnecessary trailing zeros, e.g. 2 or 0.5.
String formatQuantity(num value) => _quantityFormat.format(value);

/// Joins a quantity and optional unit, e.g. "2 chapati" or "100 g".
String formatQuantityWithUnit(num value, String? unit) {
  final quantity = formatQuantity(value);
  final label = unit?.trim();
  if (label == null || label.isEmpty) return quantity;
  return '$quantity $label';
}

/// Compact protein label, e.g. "30p". Returns null when protein is unknown.
String? formatProtein(num? protein) =>
    protein == null ? null : '${formatQuantity(protein)}p';

/// Calories followed by protein when known, e.g. "320 kcal · 12p".
String formatCaloriesWithProtein(int calories, num? protein) {
  final calorieLabel = '${formatNumber(calories)} kcal';
  final proteinLabel = formatProtein(protein);
  return proteinLabel == null ? calorieLabel : '$calorieLabel · $proteinLabel';
}

/// The quantity label shown for a logged entry.
String formatEntryQuantity(FoodEntry entry) =>
    formatQuantityWithUnit(entry.quantity, entry.unit);

String formatDateTime(DateTime value) =>
    _dateTimeFormat.format(value.toLocal());

/// Compact time label used in the recent entries list.
String formatEntryTime(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final entryDay = DateTime(local.year, local.month, local.day);
  final daysAgo = today.difference(entryDay).inDays;

  if (daysAgo == 0) return 'Today, ${_timeFormat.format(local)}';
  if (daysAgo == 1) return 'Yesterday, ${_timeFormat.format(local)}';
  return _shortDateTimeFormat.format(local);
}

String formatDayHeader(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final daysAgo = today.difference(day).inDays;

  if (daysAgo == 0) return 'Today';
  if (daysAgo == 1) return 'Yesterday';
  return _dayHeaderFormat.format(local);
}

/// Validator for optional nutrition fields: empty is allowed, otherwise the
/// value must be a non-negative number.
String? optionalNumberValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;

  final parsed = num.tryParse(text);
  if (parsed == null) return 'Enter a number';
  if (parsed < 0) return 'Cannot be negative';
  return null;
}
