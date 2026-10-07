import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/daily_screen.dart';
import 'package:carecoins_flutter/screens/onboarding_screen.dart';
import 'package:carecoins_flutter/screens/shell.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/widgets/personal_time_dialog.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

class FakeSemanticsApiClient extends ApiClient {
  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/activities')) {
      return {
        'activities': [
          {
            'id': 1,
            'title': 'Morning Walk',
            'type': 'care',
            'status': 'pending',
            'coin_value': 15,
            'starts_at': '2026-10-06T08:00:00Z',
            'duration_minutes': 30,
            'assigned_to': 1,
            'assigned_alias': 'Alex',
          },
          {
            'id': 2,
            'title': 'Quiet rest',
            'type': 'rest',
            'category': 'self',
            'status': 'approved',
            'coin_value': 0,
            'starts_at': '2026-10-06T14:00:00Z',
            'duration_minutes': 60,
            'assigned_to': 1,
          },
        ]
      };
    }
    if (path.startsWith('/api/absences')) return {'absences': []};
    if (path.startsWith('/api/personal-time')) return {'requests': []};
    if (path == '/api/me') {
      return {
        'user': {'id': 1, 'display_name': 'Parent'},
        'families': [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ],
      };
    }
    if (path == '/api/me/invites') return {'invites': []};
    return {};
  }

  @override
  Future<dynamic> post(String path, [Object? body]) async => {};
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tour.seen.welcome': true,
      'tour.seen.dashboard': true,
    });
  });

  group('T4: Screen-reader labels and semantics', () {
    testWidgets('timeline card label contains title and status and does not contain emoji', (tester) async {
      final semantics = tester.ensureSemantics();

      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeSemanticsApiClient();
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DailyScreen(date: '2026-10-06'),
        ),
      ));
      await tester.pumpAndSettle();

      final cardNode = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Morning Walk')).first,
      );

      expect(cardNode.label, contains('Morning Walk'));
      expect(cardNode.label, contains('Care'));
      expect(cardNode.label, contains('Pending'));
      expect(cardNode.label, contains('15 coins'));
      // Emojis are excluded from semantics label
      expect(cardNode.label, isNot(contains('❤️')));
      expect(cardNode.label, isNot(contains('🍽️')));
      expect(cardNode.label, isNot(contains('🧘')));
      expect(cardNode.label, isNot(contains('🏠')));

      // Personal time (self) card
      final restNode = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Quiet rest')).first,
      );

      expect(restNode.label, contains('Quiet rest'));
      expect(restNode.label, contains('Rest'));
      expect(restNode.label, contains('Approved'));
      expect(restNode.label, isNot(contains('coins')));
      expect(restNode.label, isNot(contains('🧘')));
      expect(restNode.label, isNot(contains('😴')));

      semantics.dispose();
    });

    testWidgets('selected bottom-bar tab reports isSelected and others do not', (tester) async {
      final semantics = tester.ensureSemantics();

      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeSemanticsApiClient();
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Shell(),
        ),
      ));
      await tester.pumpAndSettle();

      Finder tabFinder(String label) => find.descendant(
            of: find.byType(NavigationBar),
            matching: find.bySemanticsLabel(RegExp('^$label')),
          );

      // Tab 0 ("Today") is selected initially
      final todayTab = tester.getSemantics(tabFinder('Today'));
      expect(todayTab.flagsCollection.isSelected, ui.Tristate.isTrue);
      expect(todayTab.flagsCollection.isButton, isTrue);

      final familyTab = tester.getSemantics(tabFinder('Family'));
      expect(familyTab.flagsCollection.isSelected, isNot(ui.Tristate.isTrue));
      expect(familyTab.flagsCollection.isButton, isTrue);

      final tasksTab = tester.getSemantics(tabFinder('Tasks'));
      expect(tasksTab.flagsCollection.isSelected, isNot(ui.Tristate.isTrue));
      expect(tasksTab.flagsCollection.isButton, isTrue);

      final rewardsTab = tester.getSemantics(tabFinder('Rewards'));
      expect(rewardsTab.flagsCollection.isSelected, isNot(ui.Tristate.isTrue));

      final meTab = tester.getSemantics(tabFinder('Me'));
      expect(meTab.flagsCollection.isSelected, isNot(ui.Tristate.isTrue));

      // Tap Tasks tab
      await tester.tap(tabFinder('Tasks'));
      await tester.pumpAndSettle();

      final todayTabAfter = tester.getSemantics(tabFinder('Today'));
      expect(todayTabAfter.flagsCollection.isSelected, isNot(ui.Tristate.isTrue));

      final tasksTabAfter = tester.getSemantics(tabFinder('Tasks'));
      expect(tasksTabAfter.flagsCollection.isSelected, ui.Tristate.isTrue);

      semantics.dispose();
    });

    testWidgets('the three IconButtons have tooltips', (tester) async {
      final semantics = tester.ensureSemantics();

      final api = FakeSemanticsApiClient();
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      // 1 & 2: onboarding_screen.dart lines ~496 and ~539
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OnboardingScreen(),
        ),
      ));
      await tester.pumpAndSettle();

      // Fill step 0 family name and go to step 1
      await tester.enterText(find.byType(TextField).first, 'Smith Family');
      await tester.tap(find.widgetWithText(VButton, 'Next'));
      await tester.pumpAndSettle();

      // Step 1: Caregivers remove IconButton
      final caregiverRemoveBtn = tester.widget<IconButton>(find.byType(IconButton));
      expect(caregiverRemoveBtn.tooltip, isNotNull);
      expect(caregiverRemoveBtn.tooltip, 'Remove');

      // Go to step 2: Objects of care
      await tester.tap(find.widgetWithText(VButton, 'Next'));
      await tester.pumpAndSettle();

      // Step 2: Care object remove IconButton
      final careObjectRemoveBtn = tester.widget<IconButton>(find.byType(IconButton));
      expect(careObjectRemoveBtn.tooltip, isNotNull);
      expect(careObjectRemoveBtn.tooltip, 'Remove');

      // 3: personal_time_dialog.dart ~587 (stepper IconButtons)
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showPersonalTimeSheet(ctx, start: DateTime(2026, 9, 4, 18)),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final decreaseBtn = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove_rounded));
      expect(decreaseBtn.tooltip, isNotNull);
      expect(decreaseBtn.tooltip, 'Decrease');

      final increaseBtn = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add_rounded));
      expect(increaseBtn.tooltip, isNotNull);
      expect(increaseBtn.tooltip, 'Increase');

      semantics.dispose();
    });
  });

  // Regression: a stretch-filled Row in the bottomNavigationBar slot once
  // grew the bar to fill the screen and hid every tab's content.
  testWidgets('bottom bar is a NavigationBar with 5 destinations sitting at the bottom',
      (tester) async {
    // 600 wide is still the phone layout (< 768); narrower trips a header
    // overflow that only the monospace test font produces.
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final app = AppState(api: FakeSemanticsApiClient())
      ..families = [
        {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
      ]
      ..profile = {'id': 1, 'display_name': 'Parent'};

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Shell(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.destinations.length, 5);

    final barRect = tester.getRect(find.byType(NavigationBar));
    expect(barRect.bottom, 1000);
  });
}
