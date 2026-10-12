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
  final Map<String, dynamic> data;
  _FakeStatsApiClient(this.data);

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/stats')) return data;
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

Widget _wrap(Widget child, AppState app) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: StatsScreen(active: true)),
    ),
  );
}

Map<String, dynamic> _mockStats({
  List<String> caregivers = const ['Pablo', 'Ati'],
}) {
  return {
    'activeCaregivers': caregivers,
    'kpis': {
      'total_lifetime_coins': 250,
      'total_lifetime_tasks': 25,
      'total_bounties_offered': 20,
      'total_rewards_claimed': 4,
    },
    'memberBalances': [
      {'name': 'Pablo', 'coin_balance': 100, 'role': 'caregiver'},
      {'name': 'Ati', 'coin_balance': 150, 'role': 'caregiver'},
    ],
    'completionRates': [
      {'caregiver': 'Pablo', 'completed': 12, 'total': 15, 'waiting': 0},
      {'caregiver': 'Ati', 'completed': 6, 'total': 10, 'waiting': 2},
    ],
    'bountyStats': [
      {'name': 'Pablo', 'offered': 20, 'earned': 10, 'refunded': 5},
    ],
    'topRewards': [
      {'title': 'Ice cream', 'redemptions': 4},
    ],
    'rewardsByUser': [
      {'name': 'Pablo', 'redemptions': 3},
      {'name': 'Ati', 'redemptions': 1},
    ],
  };
}

void main() {
  setUp(() {
    statsShowEconomy = false;
    SharedPreferences.setMockInitialValues({
      'tour.seen.welcome': true,
      'tour.seen.daily': true,
      'tour.seen.dashboard': true,
      'tour.seen.stats': true,
    });
  });

  group('P6-1: Members: one card', () {
    testWidgets(
        'one card titled "This family"; 4 sentences with open bounty and most claimed reward; chip off vs on',
        (tester) async {
      tester.view.physicalSize = const Size(500, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(api: _FakeStatsApiClient(_mockStats()))
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

      // Exactly one card titled "This family"
      final familyCard = find.widgetWithText(VCard, l.membersFamilyTitle);
      expect(familyCard, findsOneWidget);
      expect(find.byType(VCard), findsOneWidget);

      // Card subtitle is statsPeriodAllTime
      final vcardWidget = tester.widget<VCard>(familyCard);
      expect(vcardWidget.subtitle, l.statsPeriodAllTime);

      // Sentence 1: Balances (reworded: "Right now 2 people hold 250 cc between them.")
      expect(find.text(l.balancesSentence('250', 2)), findsOneWidget);

      // Sentence 2: Completion (reworded: "18 of 25 due tasks done. 2 more wait...")
      final expectedCompletion =
          '${l.completionSentence(18, 25)} ${l.completionWaiting(2)}';
      expect(find.text(expectedCompletion), findsOneWidget);

      // Sentence 3: Bounties with open bounty ("5 cc still open.")
      final expectedBounties =
          '${l.bountiesSentence(20, 10, 5)} ${l.bountiesOpen(5)}';
      expect(find.text(expectedBounties), findsOneWidget);
      expect(find.textContaining('5 cc still open.'), findsOneWidget);

      // Sentence 4: Most claimed reward ("Most claimed reward: Ice cream, 4 times.")
      expect(find.text(l.rewardsTopSentence('Ice cream', 4)), findsOneWidget);
      expect(find.textContaining('Most claimed reward:'), findsOneWidget);

      // Chip off -> no _BarRow labels/names
      expect(find.text('Pablo'), findsNothing);
      expect(find.text('Ati'), findsNothing);
      expect(find.text('100 cc'), findsNothing);
      expect(find.text('150 cc'), findsNothing);
      expect(find.text(l.chartBalances), findsNothing);
      expect(find.text(l.chartCompletionRate), findsNothing);
      expect(find.text(l.chartBounties), findsNothing);
      expect(find.text(l.membersRewardsClaimed), findsNothing);
      expect(find.text(l.balancesNote), findsNothing);

      // Tap the single "By caregiver" FilterChip
      final chip = find.byType(FilterChip);
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      // Chip on -> the four sub-section labels appear
      expect(find.text(l.chartBalances), findsOneWidget);
      expect(find.text(l.chartCompletionRate), findsOneWidget);
      expect(find.text(l.chartBounties), findsOneWidget);
      expect(find.text(l.membersRewardsClaimed), findsOneWidget);

      // "12 done" (no "of")
      expect(find.text(l.completionRowDone(12)), findsOneWidget);
      expect(find.text('12 done'), findsOneWidget);
      expect(find.textContaining('12 of'), findsNothing);
      expect(find.textContaining('of 15'), findsNothing);

      // Caregiver bars appear
      expect(find.text('100 cc'), findsOneWidget);
      expect(find.text('150 cc'), findsOneWidget);
      expect(find.text(l.balancesNote), findsOneWidget);
      expect(find.text('3×'), findsOneWidget);
      expect(find.text('1×'), findsOneWidget);
    });

    testWidgets('a single caregiver -> no chip', (tester) async {
      tester.view.physicalSize = const Size(500, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(
        api: _FakeStatsApiClient(
          _mockStats(caregivers: ['Pablo']),
        ),
      )
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('en'));

      await tester.tap(find.text(l.sectionMembers));
      await tester.pumpAndSettle();

      // Single caregiver -> no chip
      expect(find.widgetWithText(VCard, l.membersFamilyTitle), findsOneWidget);
      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('all four data lists empty -> empty list (no cards)', (tester) async {
      tester.view.physicalSize = const Size(500, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final emptyStats = {
        'activeCaregivers': ['Pablo', 'Ati'],
        'memberBalances': [],
        'completionRates': [],
        'bountyStats': [],
        'topRewards': [],
        'rewardsByUser': [],
      };

      final app = AppState(api: _FakeStatsApiClient(emptyStats))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('en'));

      await tester.tap(find.text(l.sectionMembers));
      await tester.pumpAndSettle();

      expect(find.byType(VCard), findsNothing);
    });
  });
}
