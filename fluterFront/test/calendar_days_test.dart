import 'package:flutter_test/flutter_test.dart';

import 'package:carecoins_flutter/utils/dates.dart';

void main() {
  group('addCalendarDays', () {
    // Note: The DST clock-change edge cases only bite on machines in a DST time zone.
    // On such machines, `d.add(Duration(days: n))` adds n * 24 hours of elapsed time,
    // which on a 23h or 25h day lands on the wrong calendar day (e.g. 23:00 on the same
    // day or 01:00 the next day). `addCalendarDays` uses calendar day arithmetic so it
    // always lands on local midnight of the target calendar day.

    test(
        'autumn clock change: 0..8 days from 2026-10-24 gives 9 distinct consecutive dates',
        () {
      final start = DateTime(2026, 10, 24);
      final days = [for (var d = 0; d < 9; d++) addCalendarDays(start, d)];

      expect(days.length, 9);
      expect(days.toSet().length, 9);

      // 25 and 26 Oct each appear exactly once
      expect(
          days.where((d) => d.year == 2026 && d.month == 10 && d.day == 25).length,
          1);
      expect(
          days.where((d) => d.year == 2026 && d.month == 10 && d.day == 26).length,
          1);

      for (var i = 0; i < 8; i++) {
        expect(days[i].isBefore(days[i + 1]), isTrue);
      }
      expect(days[0], DateTime(2026, 10, 24));
      expect(days[1], DateTime(2026, 10, 25));
      expect(days[2], DateTime(2026, 10, 26));
      expect(days[8], DateTime(2026, 11, 1));
    });

    test(
        'spring clock change: 0..8 days from 2026-03-28 gives 9 distinct consecutive dates',
        () {
      final start = DateTime(2026, 3, 28);
      final days = [for (var d = 0; d < 9; d++) addCalendarDays(start, d)];

      expect(days.length, 9);
      expect(days.toSet().length, 9);

      // 29 and 30 Mar each appear exactly once
      expect(
          days.where((d) => d.year == 2026 && d.month == 3 && d.day == 29).length,
          1);
      expect(
          days.where((d) => d.year == 2026 && d.month == 3 && d.day == 30).length,
          1);

      for (var i = 0; i < 8; i++) {
        expect(days[i].isBefore(days[i + 1]), isTrue);
      }
      expect(days[0], DateTime(2026, 3, 28));
      expect(days[1], DateTime(2026, 3, 29));
      expect(days[2], DateTime(2026, 3, 30));
      expect(days[8], DateTime(2026, 4, 5));
    });

    test('advances correctly across month boundaries', () {
      final start = DateTime(2026, 4, 28);
      final days = [for (var d = 0; d < 6; d++) addCalendarDays(start, d)];

      expect(days.length, 6);
      expect(days.toSet().length, 6);
      expect(days[0], DateTime(2026, 4, 28));
      expect(days[1], DateTime(2026, 4, 29));
      expect(days[2], DateTime(2026, 4, 30));
      expect(days[3], DateTime(2026, 5, 1));
      expect(days[4], DateTime(2026, 5, 2));
      expect(days[5], DateTime(2026, 5, 3));
    });

    test('advances correctly across year boundaries', () {
      final start = DateTime(2026, 12, 30);
      final days = [for (var d = 0; d < 5; d++) addCalendarDays(start, d)];

      expect(days.length, 5);
      expect(days.toSet().length, 5);
      expect(days[0], DateTime(2026, 12, 30));
      expect(days[1], DateTime(2026, 12, 31));
      expect(days[2], DateTime(2027, 1, 1));
      expect(days[3], DateTime(2027, 1, 2));
      expect(days[4], DateTime(2027, 1, 3));
    });

    test('supports negative day offsets', () {
      final d = DateTime(2026, 10, 25);
      expect(addCalendarDays(d, -1), DateTime(2026, 10, 24));
      expect(addCalendarDays(d, -7), DateTime(2026, 10, 18));
    });
  });
}
