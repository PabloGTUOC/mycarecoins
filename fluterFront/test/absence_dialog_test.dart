import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/widgets/absence_dialog.dart';

/// The API rejects anything under 24 h (backend absenceService.js), so the
/// dialog must be structurally incapable of producing a shorter window.
const minAbsence = Duration(hours: 24);

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

void main() {
  group('absenceWindowFromRange', () {
    test('a single selected day is exactly the 24 h minimum', () {
      final day = DateTime(2026, 9, 4);
      final w = absenceWindowFromRange(DateTimeRange(start: day, end: day));
      expect(w.end.difference(w.start), minAbsence);
    });

    test('a multi-day range is one window per selected day', () {
      final w = absenceWindowFromRange(
          DateTimeRange(start: DateTime(2026, 9, 4), end: DateTime(2026, 9, 6)));
      expect(w.end.difference(w.start), minAbsence * 3);
    });

    test('drops any time component the picker carries over', () {
      final w = absenceWindowFromRange(DateTimeRange(
          start: DateTime(2026, 9, 4, 17, 42),
          end: DateTime(2026, 9, 4, 23, 15)));
      expect(w.start, DateTime(2026, 9, 4));
      expect(w.end, DateTime(2026, 9, 5));
    });

    test('stays at or above the minimum across a daylight-saving change', () {
      // Spring-forward loses an hour of wall clock; the window must not shrink
      // below 24 h or the API would reject it.
      for (final day in [DateTime(2026, 3, 29), DateTime(2026, 10, 25)]) {
        final w = absenceWindowFromRange(DateTimeRange(start: day, end: day));
        expect(w.end.difference(w.start) >= minAbsence, isTrue,
            reason: 'window shrank below the minimum on $day');
      }
    });
  });

  testWidgets('the dialog offers a date range and explains the whole-day rule',
      (tester) async {
    await tester.pumpWidget(_app(Builder(
      builder: (ctx) => Scaffold(
        body: ElevatedButton(
          onPressed: () =>
              showLogAbsenceDialog(ctx, day: DateTime(2026, 9, 4)),
          child: const Text('open'),
        ),
      ),
    )));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Log time off'), findsOneWidget);
    expect(
        find.textContaining('Time off covers whole days: pick one day or more.'),
        findsOneWidget);
    expect(
        find.textContaining(
            'your share of the monthly coins goes to whoever is home'),
        findsOneWidget);
    // Defaults to the anchor day only: one day, not the old 09:00-17:00 window.
    expect(find.textContaining('Dates: 4 Sep → 4 Sep · 1 day'), findsOneWidget);
  });
}
