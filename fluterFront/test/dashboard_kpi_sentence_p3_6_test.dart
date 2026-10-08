import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/dashboard_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/theme/app_theme.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

class _FakeHubApi extends ApiClient {
  List<Map<String, dynamic>> activities;
  List<Map<String, dynamic>> members;

  _FakeHubApi({
    this.activities = const [],
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
      return {'requests': []};
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
    if (path.startsWith('/api/stats')) {
      return {
        'kpis': {},
        'trend': [],
        'categories': [],
      };
    }
    if (path == '/api/me') {
      return {
        'user': {'id': 1, 'display_name': 'Parent'},
        'families': [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver'}
        ],
      };
    }
    return {};
  }

  @override
  Future<dynamic> post(String path, [Object? body]) async => {'success': true};
}

Widget _wrap(Widget child, AppState app) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      theme: buildAppTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tour.seen.welcome': true,
      'tour.seen.daily': true,
      'tour.seen.dashboard': true,
      'tour.seen.activities': true,
      'tour.seen.profile': true,
      'tour.seen.checklist-dismissed': true,
    });
  });

  group('P3-6: Family hub KPI sentence and Coming up buttons', () {
    testWidgets('Phones: no KpiCard; sentence shows "2 of your tasks wait for validation · 10 cc up for grabs"',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeHubApi(
        members: [
          {'user_id': 1, 'name': 'Parent', 'status': 'active', 'coin_balance': 100},
          {'user_id': 2, 'name': 'Partner', 'status': 'active', 'coin_balance': 50},
        ],
        activities: [
          // 2 of mine pending validation
          {
            'id': 10,
            'title': 'Task A',
            'assigned_to': 1,
            'is_template': false,
            'status': 'pending_validation',
          },
          {
            'id': 11,
            'title': 'Task B',
            'assigned_to': 1,
            'is_template': false,
            'status': 'pending_validation',
          },
          // 1 of partner's pending validation (must not be counted)
          {
            'id': 12,
            'title': 'Task C',
            'assigned_to': 2,
            'is_template': false,
            'status': 'pending_validation',
          },
          // 10 cc bounty open
          {
            'id': 13,
            'title': 'Task D',
            'assigned_to': null,
            'is_template': false,
            'status': 'pending',
            'bounty_amount': 10,
            'starts_at': DateTime.now().toIso8601String(),
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 100, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const DashboardScreen(), app));
      await tester.pumpAndSettle();

      // On phones, no KpiCard widgets render
      expect(find.byType(KpiCard), findsNothing);

      // Single sentence shows both parts joined by " · "
      expect(
        find.text('2 of your tasks wait for validation · 10 cc up for grabs'),
        findsOneWidget,
      );
    });

    testWidgets('Phones: sentence handles singular "1 of your tasks waits for validation"',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeHubApi(
        members: [
          {'user_id': 1, 'name': 'Parent', 'status': 'active', 'coin_balance': 100},
        ],
        activities: [
          // 1 of mine pending validation
          {
            'id': 10,
            'title': 'Task A',
            'assigned_to': 1,
            'is_template': false,
            'status': 'pending_validation',
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 100, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const DashboardScreen(), app));
      await tester.pumpAndSettle();

      expect(find.byType(KpiCard), findsNothing);
      expect(
        find.text('1 of your tasks waits for validation'),
        findsOneWidget,
      );
    });

    testWidgets('Phones: sentence omitted entirely when neither part applies',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeHubApi(
        members: [
          {'user_id': 1, 'name': 'Parent', 'status': 'active', 'coin_balance': 100},
        ],
        activities: [
          // Completed activity with no bounty
          {
            'id': 1,
            'title': 'Done task',
            'assigned_to': 1,
            'is_template': false,
            'status': 'completed',
            'bounty_amount': 0,
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 100, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const DashboardScreen(), app));
      await tester.pumpAndSettle();

      // No KpiCards
      expect(find.byType(KpiCard), findsNothing);

      // No sentence rendered
      expect(find.textContaining('validation'), findsNothing);
      expect(find.textContaining('up for grabs'), findsNothing);
    });

    testWidgets('Wide: the four KpiCards still render', (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeHubApi(
        members: [
          {'user_id': 1, 'name': 'Parent', 'status': 'active', 'coin_balance': 100},
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 100, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const DashboardScreen(), app));
      await tester.pumpAndSettle();

      // On wide layout, 4 KpiCards are rendered
      expect(find.byType(KpiCard), findsNWidgets(4));
      expect(find.text('Family balance'), findsOneWidget);
      expect(find.text('Tasks today'), findsOneWidget);
      expect(find.text('Open bounties'), findsOneWidget);
      expect(find.text('Recent activity'), findsAtLeastNWidgets(1));
    });

    testWidgets('Coming up: chevron IconButtons with prev/next tooltips, TextButton for time off, no «/» glyphs',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeHubApi(
        members: [
          {'user_id': 1, 'name': 'Parent', 'status': 'active', 'coin_balance': 100},
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 100, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const DashboardScreen(), app));
      await tester.pumpAndSettle();

      // Chevron IconButtons with tooltips
      final prevBtn = find.widgetWithIcon(IconButton, Icons.chevron_left_rounded);
      final nextBtn = find.widgetWithIcon(IconButton, Icons.chevron_right_rounded);
      expect(prevBtn, findsOneWidget);
      expect(nextBtn, findsOneWidget);

      final prevWidget = tester.widget<IconButton>(prevBtn);
      final nextWidget = tester.widget<IconButton>(nextBtn);
      expect(prevWidget.tooltip, 'Previous week');
      expect(nextWidget.tooltip, 'Next week');

      // No « or » glyph text buttons
      expect(find.text('«'), findsNothing);
      expect(find.text('»'), findsNothing);

      // Log time off is a TextButton with add icon and label "Log time off" without "+"
      final timeOffBtn = find.widgetWithIcon(TextButton, Icons.add_rounded);
      expect(timeOffBtn, findsOneWidget);
      expect(
        find.descendant(of: timeOffBtn, matching: find.text('Log time off')),
        findsOneWidget,
      );
      expect(find.text('+ Log time off'), findsNothing);
    });
  });
}
