import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/stats_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/widgets/charts.dart';

class _FakeStatsApi extends ApiClient {
  final Map<String, dynamic> data;

  _FakeStatsApi(this.data);

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

Widget _wrapRoute(AppState app) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(statsRoute()),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Map<String, dynamic> _buildMockData({required List<String> caregivers}) {
  return {
    'activeCaregivers': caregivers,
    'kpis': {
      'total_lifetime_coins': 120,
      'total_lifetime_tasks': 15,
      'total_bounties_offered': 2,
      'total_rewards_claimed': 3,
    },
    'trendByMonth': [
      {'month': '2026-09', 'coins': 20, 'caregiver': caregivers.first},
      if (caregivers.length > 1)
        {'month': '2026-09', 'coins': 10, 'caregiver': caregivers[1]},
      {'month': '2026-10', 'coins': 30, 'caregiver': caregivers.first},
      if (caregivers.length > 1)
        {'month': '2026-10', 'coins': 15, 'caregiver': caregivers[1]},
    ],
    'typeSplit': [
      {'type': 'care', 'caregiver': caregivers.first, 'value': 20},
      if (caregivers.length > 1)
        {'type': 'care', 'caregiver': caregivers[1], 'value': 10},
      {'type': 'household', 'caregiver': caregivers.first, 'value': 15},
      if (caregivers.length > 1)
        {'type': 'household', 'caregiver': caregivers[1], 'value': 5},
    ],
    'activityFrequency': [
      {'title': 'Cooking', 'caregiver': caregivers.first, 'value': 5},
      if (caregivers.length > 1)
        {'title': 'Cooking', 'caregiver': caregivers[1], 'value': 3},
      {'title': 'Bath', 'caregiver': caregivers.first, 'value': 2},
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

  group('P2-13: Stats route styling and compare controls', () {
    testWidgets('no Switch on Stats and AppBar shows title with 16 horizontal padding',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(api: _FakeStatsApi(_buildMockData(caregivers: ['Pablo', 'Ati'])))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrapRoute(app));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // No switch anywhere on Stats
      expect(find.byType(Switch), findsNothing);

      // AppBar contains title
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Family stats')),
        findsOneWidget,
      );

      // Body is padded horizontally by 16
      final paddingFinder = find.byWidgetPredicate(
        (w) =>
            w is Padding &&
            w.padding == const EdgeInsets.symmetric(horizontal: 16) &&
            w.child is StatsScreen,
      );
      expect(paddingFinder, findsOneWidget);
    });

    testWidgets('each of the three cards has the chip with 2+ caregivers and none with 1',
        (tester) async {
      tester.view.physicalSize = const Size(500, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 1. With 2 caregivers: all 3 cards show the FilterChip
      final appTwo = AppState(api: _FakeStatsApi(_buildMockData(caregivers: ['Pablo', 'Ati'])))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrapRoute(appTwo));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final chips = find.byType(FilterChip);
      expect(chips, findsNWidgets(3));
      expect(find.text('By caregiver'), findsNWidgets(3));

      // Each FilterChip is unselected initially
      for (int i = 0; i < 3; i++) {
        final chipWidget = tester.widget<FilterChip>(chips.at(i));
        expect(chipWidget.selected, isFalse);
      }

      // Pop route
      await tester.pageBack();
      await tester.pumpAndSettle();

      // 2. With 1 caregiver: no chips appear
      final appOne = AppState(api: _FakeStatsApi(_buildMockData(caregivers: ['Pablo'])))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrapRoute(appOne));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(FilterChip), findsNothing);
      expect(find.text('By caregiver'), findsNothing);
    });

    testWidgets('toggling one card chip changes only that card', (tester) async {
      tester.view.physicalSize = const Size(500, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(api: _FakeStatsApi(_buildMockData(caregivers: ['Pablo', 'Ati'])))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrapRoute(app));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Initially:
      // Card 1 (Income trend): LineAreaChart (single aggregated curve)
      expect(find.byType(LineAreaChart), findsOneWidget);
      expect(find.byType(MultiLineChart), findsNothing);
      // Card 2 (Category balance): DonutChart
      expect(find.byType(DonutChart), findsOneWidget);

      final chips = find.byType(FilterChip);
      expect(chips, findsNWidgets(3));

      // 1. Toggle chip on Card 1 (Income trend)
      await tester.tap(chips.at(0));
      await tester.pumpAndSettle();

      // Card 1 is now MultiLineChart
      expect(find.byType(MultiLineChart), findsOneWidget);
      expect(find.byType(LineAreaChart), findsNothing);
      // Card 2 STILL DonutChart (unchanged!)
      expect(find.byType(DonutChart), findsOneWidget);
      // Card 3 STILL uncompared
      final chip2 = tester.widget<FilterChip>(chips.at(1));
      final chip3 = tester.widget<FilterChip>(chips.at(2));
      expect(chip2.selected, isFalse);
      expect(chip3.selected, isFalse);

      // 2. Toggle chip on Card 2 (Category balance)
      await tester.tap(chips.at(1));
      await tester.pumpAndSettle();

      // Card 1 STILL MultiLineChart
      expect(find.byType(MultiLineChart), findsOneWidget);
      // Card 2 now shows caregiver bars instead of DonutChart
      expect(find.byType(DonutChart), findsNothing);
      // Card 3 STILL uncompared
      expect(tester.widget<FilterChip>(chips.at(2)).selected, isFalse);

      // 3. Toggle chip on Card 3 (Task frequency)
      await tester.tap(chips.at(2));
      await tester.pumpAndSettle();

      expect(tester.widget<FilterChip>(chips.at(0)).selected, isTrue);
      expect(tester.widget<FilterChip>(chips.at(1)).selected, isTrue);
      expect(tester.widget<FilterChip>(chips.at(2)).selected, isTrue);

      // 4. Untoggle chip on Card 1
      await tester.tap(chips.at(0));
      await tester.pumpAndSettle();

      // Card 1 reverts to LineAreaChart
      expect(find.byType(LineAreaChart), findsOneWidget);
      expect(find.byType(MultiLineChart), findsNothing);
      // Card 2 and 3 remain compared
      expect(tester.widget<FilterChip>(chips.at(1)).selected, isTrue);
      expect(tester.widget<FilterChip>(chips.at(2)).selected, isTrue);
    });

    test('tourCompareBody has updated copy in all 4 languages', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(en.tourCompareBody, "Tap By caregiver on a chart to split it by caregiver.");

      final es = lookupAppLocalizations(const Locale('es'));
      expect(es.tourCompareBody, "Toca Por cuidador en un gráfico para separarlo por cuidador.");

      final fr = lookupAppLocalizations(const Locale('fr'));
      expect(fr.tourCompareBody, "Appuyez sur Par aidant sur un graphique pour le répartir par aidant.");

      final de = lookupAppLocalizations(const Locale('de'));
      expect(de.tourCompareBody, "Tippe in einem Diagramm auf Nach Betreuenden, um es nach Betreuenden aufzuteilen.");
    });
  });
}
