/// Date helpers shared by storage and UI code.
///
/// Dates are always normalised to the user's local timezone before they are
/// turned into a file key or a day boundary.
String dateKey(DateTime value) {
  final local = value.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// Returns [value] at local midnight, which is the canonical key for a daily
/// log in memory.
DateTime dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool isSameDate(DateTime a, DateTime b) => dateKey(a) == dateKey(b);
