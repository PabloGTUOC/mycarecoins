import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_front/app_state.dart';
import 'package:admin_front/auth.dart';
import 'package:admin_front/main.dart';
import 'package:admin_front/screens/overview_screen.dart';
import 'package:admin_front/strings.dart';
import 'package:admin_front/theme.dart';
import 'package:provider/provider.dart';
import 'fakes.dart';

void main() {
  late FakeAuthService auth;
  late FakeAdminApi api;
  late AppState state;

  final testNow = DateTime.parse('2026-10-16T12:00:00.000Z');

  final fullOverviewData = {
    'families': {
      'total': 50,
      'byHeartbeat': {'active': 30, 'dormant': 15, 'inactive': 5},
      'byPlan': {'free': 40, 'pro': 10},
      'byStatus': {'active': 48, 'canceled': 2},
      'byStore': {'app_store': 8, 'play_store': 2, 'none': 40},
    },
    'freePlans': {
      'activeGrants': 4,
      'familiesCount': 3,
    },
    'mirror': {
      'mirror': 'on',
      'pending': 1,
      'synced': 10,
      'failed': 2,
      'oldestPendingAgeMinutes': 15,
    },
    'webhooks': {
      'lastEventAt': '2026-10-16T11:45:00.000Z',
      'eventsLast30Days': 120,
      'unattributedLast30Days': 3,
      'unprocessedLast30Days': 1,
      'recentEvents': [
        {
          'id': 101,
          'eventType': 'INITIAL_PURCHASE',
          'createdAt': '2026-10-16T11:00:00.000Z',
        },
      ],
    },
    'revenueCat': {
      'metrics': [
        {
          'id': 'overview/mrr',
          'name': 'MRR',
          'value': 12450.5,
          'unit': 'USD',
          'period': 'P0D',
        },
      ],
    },
  };

  setUp(() {
    auth = FakeAuthService(
      initialUser: const OperatorUser(
        uid: 'op_1',
        email: 'operator@carecoins.app',
      ),
    );
    api = FakeAdminApi();
    state = AppState(api: api, auth: auth);
  });

  tearDown(() {
    auth.dispose();
  });

  Widget buildTestWidget({DateTime Function()? nowFn}) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildAdminTheme(),
        home: OverviewScreen(nowFn: nowFn ?? () => testNow),
      ),
    );
  }

  testWidgets('renders a full fake response with cards, tables, and RC metrics',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/overview'] = fullOverviewData;

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // 1. Families card
    expect(find.text(Strings.cardFamiliesTitle), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('15'), findsWidgets); // dormant & oldestPending
    expect(find.text('5'), findsOneWidget);

    // 2. Active Free Plans card
    expect(find.text(Strings.cardFreePlansTitle), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsWidgets); // familiesCount & unattributed

    // 3. Mirror card
    expect(find.text(Strings.cardMirrorTitle), findsOneWidget);
    expect(find.text(Strings.labelMirrorOn), findsOneWidget);
    expect(find.text('10'), findsWidgets); // synced & pro plan
    expect(find.text('1'), findsWidgets); // pending & unprocessed
    expect(find.text('2'), findsWidgets); // failed & canceled & play_store
    expect(find.text('15m'), findsOneWidget);

    // 4. Webhooks card
    expect(find.text(Strings.cardWebhooksTitle), findsOneWidget);
    expect(find.text('15 minutes ago'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);

    // Expand recent webhook issues
    await tester.tap(find.text(Strings.recentWebhookIssues));
    await tester.pumpAndSettle();
    expect(find.text('#101'), findsOneWidget);
    expect(find.text('INITIAL_PURCHASE'), findsOneWidget);

    // 5. Breakdown tables
    expect(find.text(Strings.byPlanTitle), findsOneWidget);
    expect(find.text('free'), findsOneWidget);
    expect(find.text('40'), findsWidgets); // free plan & none store
    expect(find.text(Strings.byStatusTitle), findsOneWidget);
    expect(find.text('active'), findsWidgets);
    expect(find.text('48'), findsOneWidget);
    expect(find.text(Strings.byStoreTitle), findsOneWidget);
    expect(find.text('app_store'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);

    // 6. RevenueCat metrics card
    expect(find.text(Strings.cardRevenueCatTitle), findsOneWidget);
    expect(find.text('MRR'), findsOneWidget);
    expect(find.text('12450.5 USD'), findsOneWidget);

    // 7. Refresh button
    api.responses['GET:/overview?refresh=1'] = fullOverviewData;
    await tester.tap(find.text(Strings.refreshBtn));
    await tester.pumpAndSettle();

    final refreshCall = api.callHistory.lastWhere(
      (c) => c.method == 'GET' && c.path.contains('/overview'),
    );
    expect(refreshCall.path, contains('refresh=1'));
  });

  testWidgets('renders RevenueCat not configured state when null',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final notConfiguredData = Map<String, dynamic>.from(fullOverviewData);
    notConfiguredData['revenueCat'] = null;
    notConfiguredData['mirror'] = {
      'mirror': 'off',
      'pending': 0,
      'synced': 0,
      'failed': 0,
      'oldestPendingAgeMinutes': null,
    };

    api.responses['GET:/overview'] = notConfiguredData;

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Mirror shows Off
    expect(find.text(Strings.labelMirrorOff), findsOneWidget);
    // RevenueCat card shows not configured
    expect(find.text(Strings.revenueCatNotConfigured), findsOneWidget);
    // Rest of figures intact
    expect(find.text('50'), findsOneWidget);
    expect(find.text(Strings.byPlanTitle), findsOneWidget);
  });

  testWidgets('renders RevenueCat unavailable state leaving rest intact',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final unavailableData = Map<String, dynamic>.from(fullOverviewData);
    unavailableData['revenueCat'] = {'error': 'unavailable'};

    api.responses['GET:/overview'] = unavailableData;

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // RevenueCat card shows unavailable
    expect(find.text(Strings.revenueCatUnavailable), findsOneWidget);
    // Rest of figures intact
    expect(find.text('50'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text(Strings.cardWebhooksTitle), findsOneWidget);
  });

  test('webhook age formatting and oldest pending formatting', () {
    final now = DateTime.parse('2026-10-16T12:00:00.000Z');

    expect(
      Strings.formatTimeAgo('2026-10-16T11:59:35.000Z', now: now),
      'just now',
    );
    expect(
      Strings.formatTimeAgo('2026-10-16T11:59:00.000Z', now: now),
      '1 minute ago',
    );
    expect(
      Strings.formatTimeAgo('2026-10-16T11:45:00.000Z', now: now),
      '15 minutes ago',
    );
    expect(
      Strings.formatTimeAgo('2026-10-16T11:00:00.000Z', now: now),
      '1 hour ago',
    );
    expect(
      Strings.formatTimeAgo('2026-10-16T08:00:00.000Z', now: now),
      '4 hours ago',
    );
    expect(
      Strings.formatTimeAgo('2026-10-15T12:00:00.000Z', now: now),
      '1 day ago',
    );
    expect(
      Strings.formatTimeAgo('2026-10-10T12:00:00.000Z', now: now),
      '6 days ago',
    );
    expect(Strings.formatTimeAgo(null), Strings.emptyDash);

    expect(Strings.formatAgeMinutes(null), Strings.emptyDash);
    expect(Strings.formatAgeMinutes(0), '0m');
    expect(Strings.formatAgeMinutes(15), '15m');
    expect(Strings.formatAgeMinutes(60), '1h');
    expect(Strings.formatAgeMinutes(90), '1h 30m');
    expect(Strings.formatAgeMinutes(1440), '1d');
    expect(Strings.formatAgeMinutes(1500), '1d 1h');
  });

  testWidgets('Overview is selected after sign-in', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/status'] = {'ok': true, 'adminId': 1};
    api.responses['GET:/overview'] = fullOverviewData;

    await tester.pumpWidget(AdminApp(authService: auth, api: api));
    await tester.pumpAndSettle();

    // OverviewScreen is present
    expect(find.byType(OverviewScreen), findsOneWidget);

    // Rail destination Overview is selected (destination index 0)
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.selectedIndex, 0);

    // Overview title is present
    expect(find.text(Strings.overviewTitle), findsWidgets);
  });
}
