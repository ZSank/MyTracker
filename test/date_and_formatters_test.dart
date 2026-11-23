import 'package:flutter_test/flutter_test.dart';
import 'package:junk_food_tracker/core/utils/date_key.dart';
import 'package:junk_food_tracker/shared/utils/formatters.dart';

void main() {
  group('date helpers', () {
    test('dateKey pads month and day', () {
      expect(dateKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(dateKey(DateTime(2026, 11, 23, 23, 59)), '2026-11-23');
    });

    test('dateOnly removes the time component', () {
      expect(
        dateOnly(DateTime(2026, 11, 23, 18, 45, 12, 300)),
        DateTime(2026, 11, 23),
      );
    });

    test('isSameDate ignores the time on the same local day', () {
      expect(
        isSameDate(
          DateTime(2026, 11, 23, 8, 30),
          DateTime(2026, 11, 23, 22, 15),
        ),
        isTrue,
      );
      expect(
        isSameDate(DateTime(2026, 11, 23, 23, 59), DateTime(2026, 11, 24)),
        isFalse,
      );
    });
  });

  group('formatters', () {
    test('formatNumber adds thousands separators', () {
      expect(formatNumber(0), '0');
      expect(formatNumber(950), '950');
      expect(formatNumber(2200), '2,200');
      expect(formatNumber(1234567), '1,234,567');
    });

    test('formatEntryTime labels today and yesterday', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 8, 30);
      final yesterday = DateTime(now.year, now.month, now.day - 1, 8, 30);
      final older = DateTime(now.year, now.month, now.day - 5, 8, 30);

      expect(formatEntryTime(today), startsWith('Today, '));
      expect(formatEntryTime(yesterday), startsWith('Yesterday, '));
      expect(formatEntryTime(older), isNot(startsWith('Today')));
      expect(formatEntryTime(older), contains('8:30'));
    });

    test('formatDayHeader labels today and yesterday', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final older = DateTime(now.year, now.month, now.day - 5);

      expect(formatDayHeader(today), 'Today');
      expect(formatDayHeader(yesterday), 'Yesterday');
      expect(formatDayHeader(older), isNot(anyOf('Today', 'Yesterday')));
    });

    test('formatDateTime includes both date and time', () {
      final formatted = formatDateTime(DateTime(2026, 11, 23, 14, 5));

      expect(formatted, contains('2026'));
      expect(formatted, contains('2:05'));
    });
  });
}
