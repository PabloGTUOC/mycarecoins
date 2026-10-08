import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/stats_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';

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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tour.seen.welcome': true,
      'tour.seen.daily': true,
      'tour.seen.dashboard': true,
      'tour.seen.stats': true,
    });
  });

  group('P2-5: Renamed titles in all four languages', () {
    test('English titles', () {
      final l = lookupAppLocalizations(const Locale('en'));
      expect(l.statsTitle, 'Family stats');
      expect(l.chartIncomeTrend, 'Coins earned per month');
      expect(l.kpiLifetimeCoins, 'Coins from tasks');
      expect(l.chartFairness, 'Time given and taken');
      expect(l.statsByCaregiver, 'By caregiver');
    });

    test('Spanish titles', () {
      final l = lookupAppLocalizations(const Locale('es'));
      expect(l.statsTitle, 'Estadísticas familiares');
      expect(l.chartIncomeTrend, 'Monedas ganadas al mes');
      expect(l.kpiLifetimeCoins, 'Monedas de tareas');
      expect(l.chartFairness, 'Tiempo dado y tomado');
      expect(l.statsByCaregiver, 'Por cuidador');
    });

    test('French titles', () {
      final l = lookupAppLocalizations(const Locale('fr'));
      expect(l.statsTitle, 'Statistiques familiales');
      expect(l.chartIncomeTrend, 'Pièces gagnées par mois');
      expect(l.kpiLifetimeCoins, 'Pièces issues des tâches');
      expect(l.chartFairness, 'Temps donné et pris');
      expect(l.statsByCaregiver, 'Par aidant');
    });

    test('German titles', () {
      final l = lookupAppLocalizations(const Locale('de'));
      expect(l.statsTitle, 'Familienstatistiken');
      expect(l.chartIncomeTrend, 'Verdiente Münzen pro Monat');
      expect(l.kpiLifetimeCoins, 'Münzen aus Aufgaben');
      expect(l.chartFairness, 'Gegebene und genommene Zeit');
      expect(l.statsByCaregiver, 'Nach Betreuenden');
    });
  });

  group('P2-5: Duration formatting helper', () {
    test('hoursLabel formats zero, minutes, whole hours, and mixed hours/minutes', () {
      expect(hoursLabel(0), '0 h');
      expect(hoursLabel(45), '45 min');
      expect(hoursLabel(60), '1 h');
      expect(hoursLabel(90), '1 h 30');
      expect(hoursLabel(180), '3 h');
      expect(hoursLabel(215), '3 h 35');
    });
  });

  group('P2-5: Fairness first on Overview and summary sentence', () {
    final mockStats = {
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
    };

    testWidgets('Fairness block is at top of Overview above KPI cards', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(api: _FakeStatsApiClient(mockStats))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      // Page heading has new title
      expect(find.text('Family stats'), findsOneWidget);

      // Fairness card title is present
      final fairnessTitle = find.text('Time given and taken');
      expect(fairnessTitle, findsOneWidget);

      // KPI cards are present
      final kpiCoins = find.text('Coins from tasks');
      expect(kpiCoins, findsOneWidget);

      // Fairness block appears physically above the KPI cards
      final fairnessY = tester.getTopLeft(fairnessTitle).dy;
      final kpiY = tester.getTopLeft(kpiCoins).dy;
      expect(fairnessY, lessThan(kpiY));

      // Summary sentence for the current user (Pablo):
      // "You covered 3 h for Ati and took 1 h 30 for yourself."
      final summarySentence = find.text('You covered 3 h for Ati and took 1 h 30 for yourself.');
      expect(summarySentence, findsOneWidget);

      // Trend chart title has new name
      expect(find.text('Coins earned per month'), findsOneWidget);

      // Compare chips have sentence case and are present on the charts
      expect(find.text('By caregiver'), findsWidgets);
    });

    testWidgets('Pushed from Family, Stats has its own Scaffold and back button',
        (tester) async {
      final app = AppState(api: _FakeStatsApiClient(mockStats))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      // No Scaffold around the pusher: the route must bring its own (and the page needs a way back).
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(statsRoute()),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Switch), findsNothing);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Family stats')), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('Declines are never counted; the card says so', (tester) async {
      final app = AppState(api: _FakeStatsApiClient(mockStats))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      // No decline figure anywhere (PRODUCT.md §15), but the fairness card
      // keeps its footnote saying so (personal-time-plan.md).
      expect(find.textContaining('decline', findRichText: true), findsNothing);
      expect(find.textContaining('Decline', findRichText: true), findsNothing);
      expect(find.text('Saying no is never counted. Not here, not anywhere.'),
          findsOneWidget);
    });

    test('Fairness summary in Spanish, French, German', () {
      final es = lookupAppLocalizations(const Locale('es'));
      expect(
        es.fairnessSummary('3 h', 'Ati', '1 h 30'),
        'Cubriste 3 h para Ati y te tomaste 1 h 30 para ti.',
      );

      final fr = lookupAppLocalizations(const Locale('fr'));
      expect(
        fr.fairnessSummary('3 h', 'Ati', '1 h 30'),
        'Vous avez fait 3 h de relais pour Ati et pris 1 h 30 pour vous.',
      );

      final de = lookupAppLocalizations(const Locale('de'));
      expect(
        de.fairnessSummary('3 h', 'Ati', '1 h 30'),
        'Du hast 3 h für Ati übernommen und dir 1 h 30 genommen.',
      );
    });

    testWidgets('Each chart gets a one-line text summary with Semantics', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fullMockStats = {
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

      final app = AppState(api: _FakeStatsApiClient(fullMockStats))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      // Check summaries on visible charts
      expect(find.text('You covered 3 h for Ati and took 1 h 30 for yourself.'), findsOneWidget);
      expect(find.text('Most coins in October: 35 cc'), findsOneWidget);
      expect(find.text('Most work in Care: 67%'), findsOneWidget);
      expect(find.text('Most frequent: Cooking (5×)'), findsOneWidget);
      expect(find.text('Highest balance: Ati (150 cc)'), findsOneWidget);
      expect(find.text('Overall completion rate: 70%'), findsOneWidget);
      expect(find.text('Total bounties offered: 45 cc'), findsOneWidget);

      // Verify Semantics contains the summary text for screen readers
      // Screen readers get the summary once, from the visible line.
      expect(find.bySemanticsLabel(RegExp(RegExp.escape('Most coins in October: 35 cc'))), findsOneWidget);

      // Scroll down to Economy section
      await tester.drag(find.byType(ListView), const Offset(0, -1500));
      await tester.pumpAndSettle();

      expect(find.text('Most active month: October (80 cc)'), findsOneWidget);
      expect(find.text('Most rewards claimed: Ati (5)'), findsOneWidget);
      expect(find.text('Top reward: Ice cream (8 claimed)'), findsOneWidget);
      expect(find.text('Activities completed: 70%'), findsOneWidget);

      // Screen readers get the summary once, from the visible line.
      expect(find.bySemanticsLabel(RegExp(RegExp.escape('Activities completed: 70%'))), findsOneWidget);
      semantics.dispose();
    });
  });
}
