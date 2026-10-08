import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/dashboard_screen.dart';
import 'package:carecoins_flutter/screens/shell.dart';
import 'package:carecoins_flutter/screens/stats_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/theme/app_theme.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

class FakeHubApiClient extends ApiClient {
  List<Map<String, dynamic>> activities;
  List<Map<String, dynamic>> requests;
  List<Map<String, dynamic>> members;
  List<Map<String, dynamic>> claimed;

  FakeHubApiClient({
    this.activities = const [],
    this.requests = const [],
    this.members = const [],
    this.claimed = const [],
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
      return {'rewards': [], 'claimed': claimed};
    }
    if (path.startsWith('/api/stats')) {
      return {
        'kpis': {
          'total_lifetime_coins': 120,
          'total_lifetime_tasks': 15,
          'total_bounties_offered': 2,
          'total_rewards_claimed': 3,
        },
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
  Future<dynamic> post(String path, [Object? body]) async {
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

  group('P2-2: Greeting coins earned today', () {
    testWidgets('shows "Nothing paid out yet today" when 0 coins earned today',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeHubApiClient(
        members: [
          {'user_id': 1, 'name': 'Parent', 'status': 'active', 'coin_balance': 500},
        ],
        activities: [],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const Shell(initialIndex: 1), app));
      await tester.pumpAndSettle();

      // Must say "Nothing paid out yet today"
      expect(find.textContaining('Nothing paid out yet today'), findsOneWidget);
      // Must NOT claim the family balance of 500 was earned today
      expect(find.textContaining('500 cc today'), findsNothing);
    });

    testWidgets(
        'sums coin_value + bounty_amount of care activities completed today',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);

      final api = FakeHubApiClient(
        members: [
          {'user_id': 1, 'name': 'Parent', 'status': 'active', 'coin_balance': 500},
        ],
        activities: [
          {
            'id': 1,
            'title': 'School run',
            'category': 'care',
            'status': 'completed',
            'coin_value': 20,
            'bounty_amount': 5,
            'starts_at': '${todayStr}T08:00:00Z',
          },
          {
            'id': 2,
            'title': 'Rest hour',
            'category': 'self',
            'status': 'completed',
            'coin_value': 0,
            'bounty_amount': 10,
            'starts_at': '${todayStr}T14:00:00Z',
          },
        ],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const Shell(initialIndex: 1), app));
      await tester.pumpAndSettle();

      // Category care 20 + 5 = 25 cc; category self is excluded
      expect(
          find.textContaining('Your family has earned 25 cc today'),
          findsOneWidget);
    });

    testWidgets('tapping subtitle or "Go to Today" switches to Today tab',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeHubApiClient(
        members: [
          {'user_id': 1, 'name': 'Parent', 'status': 'active', 'coin_balance': 500},
        ],
        activities: [
          {
            'id': 1,
            'title': 'Dishwasher',
            'status': 'pending_validation',
            'assigned_to': 2,
          },
        ],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const Shell(initialIndex: 1), app));
      await tester.pumpAndSettle();

      // "Go to Today" link is visible because pendingTasks > 0
      expect(find.text('Go to Today'), findsOneWidget);
      await tester.tap(find.text('Go to Today'));
      await tester.pumpAndSettle();

      // Navigated to Today tab (tab 0 selected)
      final todaySemantics = tester.getSemantics(find.bySemanticsLabel(RegExp('^Today')));
      expect(todaySemantics.flagsCollection.isSelected, ui.Tristate.isTrue);
    });
  });

  group('P2-2: Week list collapsing on the hub', () {
    testWidgets('collapses runs of consecutive empty days into single line',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      // Put a task on day + 3
      final day3 = now.add(const Duration(days: 3));
      final day3Str = DateFormat('yyyy-MM-dd').format(day3);

      final api = FakeHubApiClient(
        members: [
          {'user_id': 1, 'name': 'Parent', 'status': 'active', 'coin_balance': 100},
        ],
        activities: [
          {
            'id': 10,
            'title': 'Doctor visit',
            'category': 'care',
            'status': 'pending',
            'coin_value': 15,
            'starts_at': '${day3Str}T10:00:00Z',
          },
        ],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 100, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const Shell(initialIndex: 1), app));
      await tester.pumpAndSettle();

      // Today is shown as its own row (marked Free day)
      expect(find.text('Free day'), findsOneWidget);

      // Days +1 and +2 are empty and collapsed into a single "Free: ... to ..." line
      // Days +4 to +7 are also empty and collapsed into another "Free: ... to ..." line
      final collapsedFinder = find.textContaining('Free: ');
      expect(collapsedFinder, findsNWidgets(2));
    });
  });

  group('P2-2: Quieter KpiCard', () {
    testWidgets('renders label in sentence case without uppercasing',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KpiCard(
              label: 'Open bounties',
              value: '3',
            ),
          ),
        ),
      );

      // Label is kept in sentence case
      expect(find.text('Open bounties'), findsOneWidget);
      expect(find.text('OPEN BOUNTIES'), findsNothing);

      // Text widget has normal font weight and textSecondary color
      final textWidget = tester.widget<Text>(find.text('Open bounties'));
      expect(textWidget.style?.fontWeight, FontWeight.normal);
      expect(textWidget.style?.color, AppColors.textSecondary);

      // Value has textPrimary color when accent is omitted
      final valueWidget = tester.widget<Text>(find.text('3'));
      expect(valueWidget.style?.color, AppColors.textPrimary);
    });

    testWidgets('tapping KPI card opens Stats screen', (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeHubApiClient(
        members: [
          {'user_id': 1, 'name': 'Parent', 'status': 'active', 'coin_balance': 100},
        ],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 100, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) => Scaffold(
            body: DashboardScreen(
              onOpenStats: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StatsScreen()),
              ),
            ),
          ),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      // Scroll down to the KPI cards section
      await tester.scrollUntilVisible(
        find.text('Tasks today'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      // Tap "Tasks Today" KPI card
      await tester.tap(find.text('Tasks today'));
      await tester.pumpAndSettle();

      // StatsScreen was pushed
      expect(find.byType(StatsScreen), findsOneWidget);
    });

    testWidgets('tapping "See all stats" opens Stats screen', (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeHubApiClient(
        members: [
          {'user_id': 1, 'name': 'Parent', 'status': 'active', 'coin_balance': 100},
        ],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 100, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const Shell(initialIndex: 1), app));
      await tester.pumpAndSettle();

      // Scroll down to "See all stats"
      await tester.scrollUntilVisible(
        find.text('See all stats'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -80));
      await tester.pumpAndSettle();

      // "See all stats" link is present
      expect(find.text('See all stats'), findsOneWidget);

      await tester.tap(find.text('See all stats'));
      await tester.pumpAndSettle();

      // StatsScreen was pushed
      expect(find.byType(StatsScreen), findsOneWidget);
    });
  });

  group('P2-2: Recent activity feed', () {
    testWidgets('does not show "+0 cc" for completed personal time rows',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      final nowStr = now.toUtc().toIso8601String();

      final api = FakeHubApiClient(
        members: [
          {'user_id': 1, 'name': 'Parent', 'status': 'active', 'coin_balance': 100},
        ],
        activities: [
          {
            'id': 1,
            'title': 'Yoga break',
            'category': 'self',
            'status': 'completed',
            'coin_value': 0,
            'starts_at': nowStr,
            'assigned_to_name': 'Parent',
          },
        ],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 100, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const Shell(initialIndex: 1), app));
      await tester.pumpAndSettle();

      // "Yoga break" appears in recent activity
      expect(find.textContaining('completed Yoga break'), findsOneWidget);
      // Does not show "+0 cc"
      expect(find.text('+0 cc'), findsNothing);
    });
  });
}
