import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/stats_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/widgets/charts.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

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

Map<String, dynamic> _mockStats({
  List<Map<String, dynamic>>? typeSplit,
}) {
  return {
    'activeCaregivers': ['Pablo', 'Ati'],
    'kpis': {
      'total_lifetime_coins': 120,
      'total_lifetime_tasks': 15,
      'total_bounties_offered': 2,
      'total_rewards_claimed': 3,
    },
    'trendByMonth': [
      {'month': '2026-09', 'coins': 20, 'caregiver': 'Pablo'},
      {'month': '2026-10', 'coins': 30, 'caregiver': 'Pablo'},
      {'month': '2026-11', 'coins': 25, 'caregiver': 'Pablo'},
    ],
    'typeSplit': typeSplit ?? [
      {'type': 'care', 'caregiver': 'Pablo', 'value': 20},
      {'type': 'household', 'caregiver': 'Pablo', 'value': 10},
    ],
    'activityFrequency': [
      {'title': 'Cooking', 'caregiver': 'Pablo', 'value': 5},
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

  group('P4-4: Stats Overview without a dashboard', () {
    testWidgets('Phone size (390x844): no KpiCard; shows statsAllTimeSentence',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(api: _FakeStatsApi(_mockStats()))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('en'));

      // No KpiCards on phone
      expect(find.byType(KpiCard), findsNothing);

      // Shows single all-time sentence with KPIs
      final expectedSentence = l.statsAllTimeSentence('120', 15, 2, 3);
      expect(find.text(expectedSentence), findsOneWidget);
    });

    testWidgets('Wide size (1280x800): renders four KpiCards', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(api: _FakeStatsApi(_mockStats()))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      expect(find.byType(KpiCard), findsNWidgets(4));
    });

    testWidgets('All time prefix on the three Overview card subtitles',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(api: _FakeStatsApi(_mockStats()))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('en'));

      // 1. Coins earned per month subtitle has "All time · "
      expect(
        find.textContaining('${l.statsPeriodAllTime} · ${l.summaryCoinsPerMonth('October', 30)}'),
        findsOneWidget,
      );

      // 2. Category balance subtitle has "All time · "
      expect(
        find.textContaining('${l.statsPeriodAllTime} · ${l.summaryCategoryBalance(l.filterCare, '67%')}'),
        findsOneWidget,
      );

      // 3. Task frequency subtitle has "All time · "
      expect(
        find.textContaining('${l.statsPeriodAllTime} · ${l.summaryTaskFrequency('Cooking', 5)}'),
        findsOneWidget,
      );
    });

    testWidgets('typeSplit with only care rows renders categoryAllCare text and no DonutChart',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(
        api: _FakeStatsApi(_mockStats(typeSplit: [
          {'type': 'care', 'caregiver': 'Pablo', 'value': 7},
        ])),
      )
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('en'));

      // 100% care sentence
      expect(find.text(l.categoryAllCare(7)), findsOneWidget);
      // No DonutChart on Overview
      expect(find.byType(DonutChart), findsNothing);
      // Explanatory note is present
      expect(find.text(l.categoryBalanceNote), findsOneWidget);
    });

    testWidgets('typeSplit with mixed categories renders DonutChart and categoryBalanceNote',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(
        api: _FakeStatsApi(_mockStats(typeSplit: [
          {'type': 'care', 'caregiver': 'Pablo', 'value': 5},
          {'type': 'household', 'caregiver': 'Pablo', 'value': 2},
        ])),
      )
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('en'));

      expect(find.byType(DonutChart), findsOneWidget);
      expect(find.text(l.categoryBalanceNote), findsOneWidget);
    });

    testWidgets('LineAreaChart with <3 labels renders text list and no CustomPaint',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LineAreaChart(
              labels: const ['Sep', 'Oct'],
              values: const [3, 5],
              format: (v) => '${v.round()} cc',
            ),
          ),
        ),
      );

      expect(find.text('Sep'), findsOneWidget);
      expect(find.text('3 cc'), findsOneWidget);
      expect(find.text('Oct'), findsOneWidget);
      expect(find.text('5 cc'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(LineAreaChart),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });

    testWidgets('LineAreaChart with 3 labels paints CustomPaint', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LineAreaChart(
              labels: const ['Aug', 'Sep', 'Oct'],
              values: const [2, 3, 5],
              format: (v) => '${v.round()} cc',
            ),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(LineAreaChart),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MultiLineChart with <3 labels renders text list and no CustomPaint',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiLineChart(
              labels: const ['Sep', 'Oct'],
              series: const [
                LineSeries('Pablo', Colors.blue, [10, 20]),
                LineSeries('Ati', Colors.red, [5, 15]),
              ],
              format: (v) => '${v.round()} cc',
            ),
          ),
        ),
      );

      expect(find.text('Sep'), findsOneWidget);
      expect(find.text('Pablo 10 cc · Ati 5 cc'), findsOneWidget);
      expect(find.text('Oct'), findsOneWidget);
      expect(find.text('Pablo 20 cc · Ati 15 cc'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MultiLineChart),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });

    test('lib/widgets/charts.dart source contains no LinearGradient and no cubicTo', () {
      final source = File('lib/widgets/charts.dart').readAsStringSync();
      expect(source.contains('LinearGradient'), isFalse,
          reason: 'charts.dart must not contain LinearGradient');
      expect(source.contains('cubicTo'), isFalse,
          reason: 'charts.dart must not contain cubicTo');
    });
  });
}
