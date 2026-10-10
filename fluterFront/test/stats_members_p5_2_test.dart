import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/stats_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/theme/app_theme.dart';

class _FakeStatsApiClient extends ApiClient {
  final Map<String, dynamic> statsData;

  _FakeStatsApiClient(this.statsData);

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/stats')) return statsData;
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

Map<String, dynamic> _buildMockStats() {
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
      {'month': '2026-09', 'coins': 26, 'caregiver': 'Pablo'},
      {'month': '2026-10', 'coins': 35, 'caregiver': 'Pablo'},
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
      {'caregiver': 'Pablo', 'completed': 8, 'total': 10, 'waiting': 2},
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
      'tour.seen.welcome': true,
      'tour.seen.daily': true,
      'tour.seen.dashboard': true,
      'tour.seen.stats': true,
    });
  });

  group('P5-2: Members: fair, not competitive', () {
    testWidgets('Members tab cards: default family summaries, sorted compare, no traffic light colors',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(api: _FakeStatsApiClient(_buildMockStats()))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('en'));

      // Switch to Members tab on phone
      await tester.tap(find.text('Members'));
      await tester.pumpAndSettle();

      // 1. Balances card
      expect(find.text('Coin balance leaderboard'), findsNothing);
      expect(find.text(l.chartBalances), findsOneWidget);
      expect(find.text(l.balancesSentence('250', 2)), findsOneWidget);
      // Names "Ati" and "Pablo" are not shown as bar row labels yet
      expect(find.text('150 cc'), findsNothing);
      expect(find.text('100 cc'), findsNothing);
      expect(find.text(l.balancesNote), findsNothing);

      // Tap Balances "By caregiver" chip
      final chips = find.byType(FilterChip);
      expect(chips, findsNWidgets(3));
      await tester.tap(chips.at(0));
      await tester.pumpAndSettle();

      // Now "Ati" and "Pablo" appear sorted alphabetically
      expect(find.text('150 cc'), findsOneWidget);
      expect(find.text('100 cc'), findsOneWidget);
      final atiY = tester.getTopLeft(find.text('Ati')).dy;
      final pabloY = tester.getTopLeft(find.text('Pablo')).dy;
      expect(atiY, lessThan(pabloY));
      expect(find.text(l.balancesNote), findsOneWidget);

      // 2. Completion card
      final expectedCompletion =
          '${l.completionSentence(14, 20)} ${l.completionWaiting(2)}';
      expect(find.text(expectedCompletion), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);

      // Tap Completion "By caregiver" chip
      await tester.tap(chips.at(1));
      await tester.pumpAndSettle();

      expect(find.text(l.completionRow(8, 10)), findsOneWidget);
      expect(find.text(l.completionRow(6, 10)), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);

      // 3. Bounties card
      expect(find.text(l.bountiesSentence(45, 30, 15)), findsOneWidget);

      // Tap Bounties "By caregiver" chip
      await tester.tap(chips.at(2));
      await tester.pumpAndSettle();

      // 4. In the Members tab with every chip on, no LinearProgressIndicator
      // has valueColor set to AppColors.danger or AppColors.warning
      final indicators = tester.widgetList<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicators, isNotEmpty);
      for (final indicator in indicators) {
        final color = indicator.valueColor?.value;
        expect(color, isNotNull);
        expect(color != AppColors.danger, isTrue,
            reason: 'Members bars must not use danger (red) color');
        expect(color != AppColors.warning, isTrue,
            reason: 'Members bars must not use warning (orange) color');
      }
    });
  });
}
