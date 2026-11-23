import 'package:intl/intl.dart';

final NumberFormat _numberFormat = NumberFormat.decimalPattern();
final DateFormat _timeFormat = DateFormat.jm();
final DateFormat _dateTimeFormat = DateFormat.yMMMd().add_jm();
final DateFormat _shortDateTimeFormat = DateFormat('MMM d, h:mm a');
final DateFormat _dayHeaderFormat = DateFormat('EEEE, MMM d');

String formatNumber(int value) => _numberFormat.format(value);

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
