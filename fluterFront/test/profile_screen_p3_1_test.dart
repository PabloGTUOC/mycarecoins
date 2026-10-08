import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/profile_screen.dart';
import 'package:carecoins_flutter/screens/shell.dart';
import 'package:carecoins_flutter/screens/stats_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/theme/app_theme.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

class _FakeProfileApi extends ApiClient {
  List<Map<String, dynamic>> ledgerData = [];
  String? revertedActivityId;

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/me/notification-preferences')) {
      return <String, dynamic>{};
    }
    if (path.startsWith('/api/families/') &&
        path.contains('/deletion-requests')) {
      return {'deletionRequests': []};
    }
    if (path.startsWith('/api/me/ledger')) {
      return {'ledger': ledgerData};
    }
    if (path.startsWith('/api/activities')) return {'activities': []};
    if (path.startsWith('/api/absences')) return {'absences': []};
    if (path.startsWith('/api/personal-time')) return {'requests': []};
    if (path.startsWith('/api/dashboard/')) {
      return {'members': [], 'calendar': [], 'objectsOfCare': []};
    }
    if (path.startsWith('/api/marketplace/rewards/')) {
      return {'rewards': [], 'claimed': []};
    }
    if (path.startsWith('/api/stats')) {
      return {
        'activeCaregivers': ['Dad'],
        'kpis': {},
        'monthlyChart': [],
        'distribution': [],
      };
    }
    if (path == '/api/me') {
      return {
        'user': {'id': 1, 'display_name': 'Dad'},
        'families': [
          {
            'family_id': 101,
            'name': 'The Henderson Family',
            'role': 'caregiver',
            'alias': 'Dad',
            'coin_balance': 488,
          }
        ],
      };
    }
    return {};
  }

  @override
  Future<dynamic> post(String path, [Object? body]) async {
    if (path.endsWith('/revert')) {
      final segments = path.split('/');
      revertedActivityId = segments[segments.length - 2];
      return {'success': true};
    }
    return {'success': true};
  }

  @override
  Future<dynamic> put(String path, [Object? body]) async {
    return {'success': true};
  }
}

Widget _wrap(Widget child, AppState app, {ThemeData? theme}) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      theme: theme ?? buildAppTheme(),
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
      'tour.seen.activities': true,
      'tour.seen.profile': true,
    });
  });

  group('P3-1: Source scan', () {
    test('profile_screen.dart has no LinearGradient, no AppColors.ink, no SegmentedTabs', () {
      final file = File('lib/screens/profile_screen.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();

      expect(source, isNot(contains('LinearGradient')),
          reason: 'Gradient banner must be removed in favour of plain text line');
      expect(source, isNot(contains('AppColors.ink')),
          reason: 'Dark wallet card must be replaced with light AppColors.surface block');
      expect(source, isNot(contains('SegmentedTabs')),
          reason: 'Phone layout must not use SegmentedTabs');
    });
  });

  group('P3-1: Me is one page on phones', () {
    testWidgets('no SegmentedTabs on phones; section titles appear in order Wallet, Family, You',
        (tester) async {
      tester.view.physicalSize = const Size(500, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeProfileApi();
      final app = AppState(api: api)
        ..families = [
          {
            'family_id': 101,
            'name': 'The Henderson Family',
            'role': 'caregiver',
            'alias': 'Dad',
            'coin_balance': 488,
          }
        ]
        ..profile = {'id': 1, 'display_name': 'Dad'};

      await tester.pumpWidget(_wrap(const Scaffold(body: ProfileScreen()), app));
      await tester.pumpAndSettle();

      // No segmented tabs
      expect(find.byType(SegmentedTabs), findsNothing);

      // Identity line under app bar title
      expect(find.text('The Henderson Family · Dad'), findsOneWidget);

      // Section titles
      final walletTitle = find.text('Wallet');
      final familyTitle = find.text('Family');
      final youTitle = find.text('You');

      expect(walletTitle, findsOneWidget);
      expect(familyTitle, findsOneWidget);
      expect(youTitle, findsOneWidget);

      final walletTop = tester.getTopLeft(walletTitle).dy;
      final familyTop = tester.getTopLeft(familyTitle).dy;
      final youTop = tester.getTopLeft(youTitle).dy;

      // Order: Wallet < Family < You
      expect(walletTop, lessThan(familyTop));
      expect(familyTop, lessThan(youTop));
    });

    testWidgets('wallet balance reads "488 cc" with "Your balance" label',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeProfileApi();
      final app = AppState(api: api)
        ..families = [
          {
            'family_id': 101,
            'name': 'The Henderson Family',
            'role': 'caregiver',
            'alias': 'Dad',
            'coin_balance': 488,
          }
        ]
        ..profile = {'id': 1, 'display_name': 'Dad'};

      await tester.pumpWidget(_wrap(const Scaffold(body: ProfileScreen()), app));
      await tester.pumpAndSettle();

      // Label: "Your balance"
      expect(find.text('Your balance'), findsOneWidget);

      // Balance: "488 cc"
      expect(find.text('488 cc'), findsOneWidget);

      // Old dark card labels must NOT be present
      expect(find.text('Total balance'), findsNothing);
      expect(find.text('TOTAL BALANCE'), findsNothing);
      expect(find.text('Coins'), findsNothing);
    });

    testWidgets('"See family stats" row is present and opens Stats screen; no "Activity insights"',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeProfileApi();
      final app = AppState(api: api)
        ..families = [
          {
            'family_id': 101,
            'name': 'The Henderson Family',
            'role': 'caregiver',
            'alias': 'Dad',
            'coin_balance': 488,
          }
        ]
        ..profile = {'id': 1, 'display_name': 'Dad'};

      await tester.pumpWidget(_wrap(const Scaffold(body: ProfileScreen()), app));
      await tester.pumpAndSettle();

      // No activity insights card or tasks mastered
      expect(find.text('Activity insights'), findsNothing);
      expect(find.text('Tasks mastered'), findsNothing);

      // "See family stats" is present
      final statsFinder = find.text('See family stats');
      expect(statsFinder, findsOneWidget);

      // Tap "See family stats"
      await tester.tap(statsFinder);
      await tester.pumpAndSettle();

      // Pushes StatsScreen
      expect(find.byType(StatsScreen), findsOneWidget);
    });

    testWidgets('ledger preview shows at most 3 rows; "View full ledger" opens full ledger with uncheck',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeProfileApi();
      api.ledgerData = [
        {
          'activity_id': 1,
          'activity_title': 'Task One',
          'reason': 'activity_completed',
          'amount': 10,
          'created_at': DateTime.now().toIso8601String(),
        },
        {
          'activity_id': 2,
          'activity_title': 'Task Two',
          'reason': 'activity_completed',
          'amount': 20,
          'created_at': DateTime.now().toIso8601String(),
        },
        {
          'activity_id': 3,
          'activity_title': 'Task Three',
          'reason': 'activity_completed',
          'amount': 30,
          'created_at': DateTime.now().toIso8601String(),
        },
        {
          'activity_id': 4,
          'activity_title': 'Task Four',
          'reason': 'activity_completed',
          'amount': 40,
          'created_at': DateTime.now().toIso8601String(),
        },
        {
          'activity_id': 5,
          'activity_title': 'Task Five',
          'reason': 'activity_completed',
          'amount': 50,
          'created_at': DateTime.now().toIso8601String(),
        },
      ];

      final app = AppState(api: api)
        ..families = [
          {
            'family_id': 101,
            'name': 'The Henderson Family',
            'role': 'caregiver',
            'alias': 'Dad',
            'coin_balance': 488,
          }
        ]
        ..profile = {'id': 1, 'display_name': 'Dad'};

      await tester.pumpWidget(_wrap(const Scaffold(body: ProfileScreen()), app));
      await tester.pumpAndSettle();

      // Only first 3 items shown in preview
      expect(find.text('Task One'), findsOneWidget);
      expect(find.text('Task Two'), findsOneWidget);
      expect(find.text('Task Three'), findsOneWidget);
      expect(find.text('Task Four'), findsNothing);
      expect(find.text('Task Five'), findsNothing);

      // "View full ledger" button exists
      final toggleButton = find.text('View full ledger');
      expect(toggleButton, findsOneWidget);

      // Tap to expand
      await tester.tap(toggleButton);
      await tester.pumpAndSettle();

      // Full ledger shows all tasks (Task One appears in preview and full ledger)
      expect(find.text('Monthly ledger'), findsOneWidget);
      expect(find.text('Task Four'), findsOneWidget);
      expect(find.text('Task Five'), findsOneWidget);

      // Un-check button is present on completed tasks
      final uncheckBtns = find.text('Un-check');
      expect(uncheckBtns, findsWidgets);

      // Tap first uncheck button
      await tester.tap(uncheckBtns.first);
      await tester.pumpAndSettle();

      // Confirmation dialog opens
      expect(find.text('Confirm'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      // API was called to revert
      expect(api.revertedActivityId, '1');

      // Flush snackbar timer
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Coin pill in Shell lands on Me with Wallet section visible',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeProfileApi();
      final app = AppState(api: api)
        ..families = [
          {
            'family_id': 101,
            'name': 'The Henderson Family',
            'role': 'caregiver',
            'alias': 'Dad',
            'coin_balance': 488,
          }
        ]
        ..profile = {'id': 1, 'display_name': 'Dad'};

      // Start on Family tab (index 1)
      await tester.pumpWidget(_wrap(const Shell(initialIndex: 1), app));
      await tester.pumpAndSettle();

      // Tap the coin balance pill in the app bar
      final pill = find.byType(CoinBalancePill);
      expect(pill, findsOneWidget);
      await tester.tap(pill);
      await tester.pumpAndSettle();

      // Profile screen is visible with Wallet section and balance
      expect(find.text('Wallet'), findsOneWidget);
      expect(find.text('Your balance'), findsOneWidget);
      expect(find.text('488 cc'), findsOneWidget);
    });
  });
}
