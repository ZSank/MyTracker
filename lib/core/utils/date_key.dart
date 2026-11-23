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

/// The `YYYY-MM` key used for the one-file-per-month food logs.
String monthKey(DateTime value) {
  final local = value.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$year-$month';
}

/// Returns [value] at local midnight, which is the canonical key for a daily
/// log in memory.
DateTime dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Returns the first day of [value]'s local month.
DateTime monthOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month);
}

bool isSameDate(DateTime a, DateTime b) => dateKey(a) == dateKey(b);

bool isSameMonth(DateTime a, DateTime b) => monthKey(a) == monthKey(b);
