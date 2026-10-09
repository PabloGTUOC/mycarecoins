import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/widgets/personal_time_dialog.dart';

void main() {
  group('personal-time types', () {
    test('every type the API accepts has a distinct label', () {
      // Mirrors SELF_TYPES in backend/src/services/personalTimeService.js —
      // a type the app cannot name is a type the picker cannot offer.
      expect(kPersonalTimeTypes,
          ['sport', 'social', 'rest', 'appointment', 'other']);
      final l = lookupAppLocalizations(const Locale('en'));
      final labels =
          kPersonalTimeTypes.map((t) => personalTimeTypeLabel(l, t)).toSet();
      expect(labels.length, kPersonalTimeTypes.length,
          reason: 'each type needs a label of its own');
      expect(labels.every((s) => s.isNotEmpty), isTrue);
    });

    test('an unknown type falls back rather than crashing the timeline', () {
      final l = lookupAppLocalizations(const Locale('en'));
      expect(personalTimeTypeLabel(l, 'yoga'), personalTimeTypeLabel(l, 'other'));
    });
  });

  group('personal-time repeats', () {
    testWidgets('every recurrence the API accepts has a label of its own',
        (tester) async {
      // Mirrors RECURRENCES in backend/src/services/personalTimeService.js,
      // plus the null the API means by "no recurrence".
      expect(kPersonalTimeRepeats, [null, 'daily', 'weekdays', 'weekly']);

      late AppLocalizations l;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          l = AppLocalizations.of(context);
          return const SizedBox();
        }),
      ));

      final labels =
          kPersonalTimeRepeats.map((r) => personalTimeRepeatLabel(l, r)).toSet();
      expect(labels.length, kPersonalTimeRepeats.length,
          reason: 'two repeats sharing a label would be unpickable');
    });
  });

  testWidgets('the sheet asks for a name, a type, a window and an offer',
      (tester) async {
    final app = AppState();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showPersonalTimeSheet(ctx,
                  start: DateTime(2026, 9, 4, 18)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Book personal time'), findsOneWidget);
    // Every self type is offered, so nothing forces "other" by default.
    expect(find.textContaining('Sport'), findsWidgets);
    expect(find.textContaining('Appointment'), findsWidgets);
    // The window is seeded from the slot that was double-tapped.
    expect(find.textContaining('18:00'), findsWidgets);
    // Coverage is requested by default — asking is the norm, not the exception.
    expect(find.text('Someone needs to cover'), findsOneWidget);
    expect(find.text('Add from your own coins'), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);

    // Phase 6: the repeat is offered up front, and defaults to a one-off.
    expect(find.text('Repeat'), findsOneWidget);
    expect(find.text('Just once'), findsOneWidget);
    expect(find.text('Every week'), findsOneWidget);
    // No end date is asked for until a repeat is actually chosen.
    expect(find.textContaining('Until'), findsNothing);
  });

  testWidgets('choosing a repeat offers an end date, and dropping it withdraws',
      (tester) async {
    final app = AppState();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () =>
                  showPersonalTimeSheet(ctx, start: DateTime(2026, 9, 4, 18)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Every week'));
    await tester.pumpAndSettle();
    // Four weeks out from the seed, offered rather than demanded.
    expect(find.text('Until 2 Oct 2026'), findsOneWidget);

    await tester.tap(find.text('Just once'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Until'), findsNothing);
  });
}
