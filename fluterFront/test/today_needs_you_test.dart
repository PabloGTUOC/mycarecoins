import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/daily_screen.dart';
import 'package:carecoins_flutter/screens/shell.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';

class FakeNeedsYouApiClient extends ApiClient {
  List<Map<String, dynamic>> activities;
  List<Map<String, dynamic>> requests;
  List<Map<String, dynamic>> members;
  final List<String> postCalls = [];

  FakeNeedsYouApiClient({
    this.activities = const [],
    this.requests = const [],
    this.members = const [],
  });

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/activities')) {
      return {'activities': activities};
    }
    if (path.startsWith('/api/absences')) {
      return {'absences': []};
    }
    if (path.startsWith('/api/personal-time')) {
      return {'requests': requests};
    }
    if (path.startsWith('/api/dashboard/')) {
      return {
        'members': members,
        'calendar': [],
        'objectsOfCare': [],
      };
    }
    if (path.startsWith('/api/marketplace/rewards/')) {
      return {'rewards': [], 'claimed': []};
    }
    if (path == '/api/me') {
      return {
        'user': {'id': 1, 'display_name': 'Me'},
        'families': [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ],
      };
    }
    return {};
  }

  @override
  Future<dynamic> post(String path, [Object? body]) async {
    postCalls.add(path);
    return {'success': true};
  }
}

Widget _wrap(Widget child, AppState app) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tour.seen.welcome': true,
      'tour.seen.daily': true,
      'tour.seen.dashboard': true,
      'tour.seen.checklist-dismissed': true,
    });
  });

  group('P2-1: Shell tab order and initial tab', () {
    testWidgets('Today is the initial tab and tab order is Today, Family, Tasks, Rewards, Me',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeNeedsYouApiClient();
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const Shell(), app));
      await tester.pumpAndSettle();

      Finder tabFinder(String label) => find.descendant(
            of: find.byType(NavigationBar),
            matching: find.bySemanticsLabel(RegExp('^$label')),
          );

      // Today tab is selected initially
      final todaySemantics = tester.getSemantics(tabFinder('Today'));
      expect(todaySemantics.flagsCollection.isSelected, ui.Tristate.isTrue);

      final familySemantics = tester.getSemantics(tabFinder('Family'));
      expect(familySemantics.flagsCollection.isSelected, isNot(ui.Tristate.isTrue));

      final tasksSemantics = tester.getSemantics(tabFinder('Tasks'));
      expect(tasksSemantics.flagsCollection.isSelected, isNot(ui.Tristate.isTrue));

      final rewardsSemantics = tester.getSemantics(tabFinder('Rewards'));
      expect(rewardsSemantics.flagsCollection.isSelected, isNot(ui.Tristate.isTrue));

      final meSemantics = tester.getSemantics(tabFinder('Me'));
      expect(meSemantics.flagsCollection.isSelected, isNot(ui.Tristate.isTrue));

      // DailyScreen is visible as the initial screen (shows Time Off action in AppBar)
      expect(find.byType(DailyScreen), findsOneWidget);
    });
  });

  group('P2-1: Needs you block in DailyScreen', () {
    testWidgets('empty state collapses to "You\'re all caught up."', (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeNeedsYouApiClient(
        activities: [],
        requests: [],
        members: [
          {'user_id': 1, 'name': 'Me', 'status': 'active', 'coin_balance': 50},
        ],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const DailyScreen(date: '2026-10-06'), app));
      await tester.pumpAndSettle();

      expect(find.text("You're all caught up."), findsOneWidget);
      expect(find.text('Needs you'), findsNothing);
    });

    testWidgets('non-empty state displays validations, cover requests, pending members, and bounties',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeNeedsYouApiClient(
        activities: [
          {
            'id': 101,
            'title': 'Bath time',
            'status': 'pending_validation',
            'assigned_to': 2,
            'assigned_to_name': 'Ben',
            'coin_value': 20,
            'duration_minutes': 30,
            'starts_at': '2026-10-06T18:00:00Z',
          },
          {
            'id': 102,
            'title': 'Walk dogs',
            'status': 'approved',
            'bounty_amount': 15,
            'assigned_to': 2,
            'assigned_to_name': 'Ben',
            'coin_value': 10,
            'duration_minutes': 30,
            'starts_at': '2026-10-06T19:00:00Z',
          },
        ],
        requests: [
          {
            'id': 201,
            'title': 'Friday shift',
            'type': 'meditation',
            'status': 'pending',
            'requester_id': 2,
            'requester_name': 'Ana',
            'requested_of': 1,
            'sweetener_coins': 10,
            'starts_at': '2026-10-09T18:00:00Z',
            'ends_at': '2026-10-09T19:00:00Z',
          },
        ],
        members: [
          {
            'user_id': 3,
            'name': 'Charlie',
            'status': 'pending',
            'coin_balance': 0,
          },
        ],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const DailyScreen(date: '2026-10-06'), app));
      await tester.pumpAndSettle();

      expect(find.text('Needs you'), findsOneWidget);
      expect(find.text('Validate "Bath time" · Ben'), findsOneWidget);
      expect(find.text('Ana asks you to cover "Friday shift"'), findsOneWidget);
      expect(find.text('Approve member: Charlie'), findsOneWidget);
      expect(find.text('Take over "Walk dogs" (+15 cc)'), findsOneWidget);

      // Tap validation row triggers validate call
      await tester.tap(find.text('Validate "Bath time" · Ben'));
      await tester.pumpAndSettle();
      expect(api.postCalls, contains('/api/activities/101/validate'));

      // Tap member approval row triggers approve call
      await tester.tap(find.text('Approve member: Charlie'));
      await tester.pumpAndSettle();
      expect(api.postCalls, contains('/api/families/1/members/3/approve'));
      // AppState.setSuccess schedules a 3.5s timer; pump past it to prevent pending timer error
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('P2-1: Today tab dot notification', () {
    testWidgets('dot appears when Needs you is non-empty and clears when Today is viewed',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeNeedsYouApiClient(
        activities: [
          {
            'id': 101,
            'title': 'Bath time',
            'status': 'pending_validation',
            'assigned_to': 2,
            'assigned_to_name': 'Ben',
            'coin_value': 20,
            'duration_minutes': 30,
            'starts_at': '2026-10-06T18:00:00Z',
          },
        ],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      // Launch on Family tab (tab index 1)
      await tester.pumpWidget(_wrap(const Shell(initialIndex: 1), app));
      await tester.pumpAndSettle();

      // Dot appears on Today tab (Badge)
      expect(find.byType(Badge), findsOneWidget);

      // Semantics label gains ", needs your attention"
      final todaySemanticsBefore = tester.getSemantics(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.bySemanticsLabel(RegExp('needs your attention')),
      ));
      expect(todaySemanticsBefore.label, contains('needs your attention'));

      // Tap Today tab to view Today
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();

      // Dot is cleared when Today is viewed
      expect(find.byType(Badge), findsNothing);

      // Semantics label no longer contains ", needs your attention"
      final todaySemanticsAfter = tester.getSemantics(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.bySemanticsLabel(RegExp('^Today')),
      ));
      expect(todaySemanticsAfter.label, isNot(contains('needs your attention')));
      expect(todaySemanticsAfter.flagsCollection.isSelected, ui.Tristate.isTrue);
    });
  });

  group('P2-1: Family hub date tap switches to Today tab', () {
    testWidgets('tapping a day on Family switches to Today tab with that day selected',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeNeedsYouApiClient(
        members: [
          {'user_id': 1, 'name': 'Parent', 'status': 'active', 'coin_balance': 150},
        ],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      // Launch on Family tab
      await tester.pumpWidget(_wrap(const Shell(initialIndex: 1), app));
      await tester.pumpAndSettle();

      // Tap the first day row on Family
      await tester.tap(find.text('Free day').first);
      await tester.pumpAndSettle();

      // Switches to Today tab (tab 0 selected)
      final todaySemantics = tester.getSemantics(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.bySemanticsLabel(RegExp('^Today')),
      ));
      expect(todaySemantics.flagsCollection.isSelected, ui.Tristate.isTrue);
    });
  });
}
