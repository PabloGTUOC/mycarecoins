import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/stats_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

class _FakeStatsApiClient extends ApiClient {
  final Map<String, dynamic> statsData;

  _FakeStatsApiClient(this.statsData);

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/stats')) {
      return statsData;
    }
    if (path == '/api/me') {
      return {
        'user': {'id': 1, 'display_name': 'Pablo'},
        'families': [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ],
      };
    }
    return {};
  }
}

Widget _wrap(Widget child, AppState app, [Locale locale = const Locale('en')]) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Map<String, dynamic> _fullMockStats() {
  return {
    'activeCaregivers': ['Pablo', 'Ati'],
    'kpis': {
      'total_lifetime_coins': 120,
      'total_lifetime_tasks': 15,
      'total_bounties_offered': 2,
      'total_rewards_claimed': 3,
    },
    'fairnessByMonth': [
      {
        'caregiver': 'Ati',
        'personal_minutes': 180,
        'coverage_minutes': 60,
        'month': '2026-10',
      },
      {
        'caregiver': 'Pablo',
        'personal_minutes': 90,
        'coverage_minutes': 180,
        'month': '2026-10',
      },
    ],
    'trendByMonth': [
      {
        'month': '2026-09',
        'coins': 26,
        'caregiver': 'Pablo',
      },
      {
        'month': '2026-10',
        'coins': 35,
        'caregiver': 'Pablo',
      },
    ],
    'typeSplit': [
      {'type': 'care', 'caregiver': 'Pablo', 'value': 20},
      {'type': 'household', 'caregiver': 'Pablo', 'value': 10},
    ],
    'activityFrequency': [
      {'title': 'Cooking', 'caregiver': 'Pablo', 'value': 5},
    ],
    'memberBalances': [
      {'name': 'Ati', 'coin_balance': 150, 'role': 'caregiver'},
      {'name': 'Pablo', 'coin_balance': 100, 'role': 'caregiver'},
    ],
    'completionRates': [
      {'caregiver': 'Pablo', 'completed': 8, 'total': 10},
      {'caregiver': 'Ati', 'completed': 6, 'total': 10},
    ],
    'bountyStats': [
      {'name': 'Pablo', 'offered': 45, 'earned': 30, 'refunded': 15},
    ],
    'coinFlowByReason': [
      {'month': '2026-10', 'reason': 'activity_completed', 'total': 80},
    ],
    'rewardsByUser': [
      {'name': 'Ati', 'redemptions': 5},
    ],
    'topRewards': [
      {'title': 'Ice cream', 'redemptions': 8},
    ],
    'statusDistribution': [
      {'status': 'completed', 'count': 14},
      {'status': 'pending', 'count': 6},
    ],
  };
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tour.seen.stats': true,
    });
  });

  tearDown(() {
    statsShowEconomy = true;
  });

  group('P5-3: Economy leaves the family app', () {
    testWidgets('statsShowEconomy = false, phone (390x844): SegmentedTabs has Overview and Members only',
        (tester) async {
      statsShowEconomy = false;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(api: _FakeStatsApiClient(_fullMockStats()))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('en'));

      expect(find.text(l.tabOverview), findsOneWidget);
      expect(find.text(l.sectionMembers), findsOneWidget);
      expect(find.text(l.tabEconomy), findsNothing);
    });

    testWidgets('statsShowEconomy = false, wide (1280x800): no sectionEconomy, no chartCoinFlow or chartStatusDist',
        (tester) async {
      statsShowEconomy = false;
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(api: _FakeStatsApiClient(_fullMockStats()))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('en'));

      expect(find.text(l.sectionEconomy), findsNothing);
      expect(find.text(l.chartCoinFlow), findsNothing);
      expect(find.text(l.chartStatusDist), findsNothing);
    });

    testWidgets(
        'statsShowEconomy = false, phone, Members tab: chartTopRewards shows Ice cream 8×, and Ati 5× after chip tap',
        (tester) async {
      statsShowEconomy = false;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(api: _FakeStatsApiClient(_fullMockStats()))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('en'));

      // Switch to Members tab
      await tester.tap(find.text(l.sectionMembers));
      await tester.pumpAndSettle();

      // Scroll to chartTopRewards card
      final rewardsCard = find.widgetWithText(VCard, l.chartTopRewards);
      await tester.scrollUntilVisible(rewardsCard, 300);
      await tester.pumpAndSettle();

      expect(find.text(l.chartTopRewards), findsOneWidget);
      expect(find.text('Ice cream'), findsOneWidget);
      expect(find.text('8×'), findsOneWidget);
      expect(find.text('5×'), findsNothing);

      // Tap compare chip on the rewards card
      final chip = find.descendant(of: rewardsCard, matching: find.byType(FilterChip));
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(find.text('5×'), findsOneWidget);
      expect(find.text('Ice cream'), findsNothing);
      expect(find.text('8×'), findsNothing);
    });

    testWidgets('statsShowEconomy = true, phone: Economy tab exists and shows chartCoinFlow',
        (tester) async {
      statsShowEconomy = true;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(api: _FakeStatsApiClient(_fullMockStats()))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('en'));

      expect(find.text(l.tabEconomy), findsOneWidget);

      await tester.tap(find.text(l.tabEconomy));
      await tester.pumpAndSettle();

      expect(find.text(l.chartCoinFlow), findsOneWidget);
    });

    testWidgets('rewardsNoneClaimed is displayed when all top rewards have zero redemptions',
        (tester) async {
      statsShowEconomy = false;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final statsWithZeroRewards = _fullMockStats()
        ..['topRewards'] = [
          {'title': 'Ice cream', 'redemptions': 0},
        ];

      final app = AppState(api: _FakeStatsApiClient(statsWithZeroRewards))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('en'));

      await tester.tap(find.text(l.sectionMembers));
      await tester.pumpAndSettle();

      final rewardsCard = find.widgetWithText(VCard, l.chartTopRewards);
      await tester.scrollUntilVisible(rewardsCard, 300);
      await tester.pumpAndSettle();

      expect(find.text(l.rewardsNoneClaimed), findsOneWidget);
      expect(find.text('Ice cream'), findsNothing);
    });
  });
}
