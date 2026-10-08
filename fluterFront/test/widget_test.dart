import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/services/tour_service.dart';
import 'package:carecoins_flutter/widgets/activation_checklist.dart';
import 'package:carecoins_flutter/widgets/coach_marks.dart';
import 'package:carecoins_flutter/widgets/help_sheet.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

/// Wraps [home] in a MaterialApp with the localization delegates so widgets
/// that call AppLocalizations.of(context) resolve to English in tests.
Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

void main() {
  testWidgets('UI kit smoke test: VButton, KpiCard and PillBadge render',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              VButton(child: Text('Sign In')),
              KpiCard(label: 'Family coins', value: '120', unit: 'cc'),
              PillBadge(text: '+5cc'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Family coins'), findsOneWidget);
    expect(find.text('+5cc'), findsOneWidget);
  });

  testWidgets('help sheet opens and shows steps, glossary and FAQ',
      (tester) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showHelpSheet(context),
                child: const Text('open help'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open help'));
    await tester.pumpAndSettle();

    expect(find.text('How CareCoins works'), findsOneWidget);
    expect(find.text('Define tasks'), findsOneWidget);

    // Glossary and FAQ are lazily built further down the sheet's ListView.
    await tester.scrollUntilVisible(find.text('CareCoin (cc)'), 200);
    expect(find.text('CareCoin (cc)'), findsOneWidget);

    // FAQ answers expand on tap.
    final question = find.text('Where do coins come from?');
    await tester.scrollUntilVisible(question, 200);
    // Bring it clear of the sheet's bottom edge before tapping.
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -150));
    await tester.pumpAndSettle();
    await tester.tap(question);
    await tester.pumpAndSettle();
    expect(find.textContaining('monthly budget'), findsWidgets);
  });

  testWidgets('EmptyState renders title, body and action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.storefront_rounded,
            title: 'The reward store is empty',
            body: 'Rewards are what coins are for.',
            actionLabel: 'Create a reward',
            onAction: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('The reward store is empty'), findsOneWidget);
    await tester.tap(find.text('Create a reward'));
    expect(tapped, isTrue);
  });

  testWidgets('coach marks spotlight a target, advance and persist',
      (tester) async {
    // Welcome already decided so the tab tour is allowed to run.
    SharedPreferences.setMockInitialValues({'tour.seen.welcome': true});
    final targetKey = GlobalKey();
    late BuildContext ctx;

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(builder: (c) {
            ctx = c;
            return Center(
                child: Container(
                    key: targetKey,
                    width: 120,
                    height: 40,
                    color: Colors.blue));
          }),
        ),
      ),
    );

    final tour = maybeShowTour(ctx, 'test-tour', [
      CoachMark(
          targetKey: targetKey,
          title: 'The thing',
          body: 'This is what the thing does.'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('The thing'), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    await tour;

    expect(find.text('The thing'), findsNothing);
    expect(await TourService.I.hasSeen('test-tour'), isTrue);
  });

  testWidgets('activation checklist shows progress and deep-links',
      (tester) async {
    var wentToStore = false;
    var dismissed = false;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ActivationChecklist(
            steps: [
              ChecklistStep(
                  label: 'Create a task template', done: true, onGo: () {}),
              ChecklistStep(
                  label: 'Stock the reward store',
                  done: false,
                  onGo: () => wentToStore = true),
            ],
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );

    expect(find.text('Get your family going'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);

    // Pending steps deep-link; done steps don't.
    await tester.tap(find.text('Stock the reward store'));
    expect(wentToStore, isTrue);

    await tester.tap(find.byTooltip('Dismiss checklist'));
    expect(dismissed, isTrue);
  });
}
