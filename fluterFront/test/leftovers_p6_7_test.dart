import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/activities_screen.dart';
import 'package:carecoins_flutter/screens/stats_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/theme/app_theme.dart';

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

class _FakeActivitiesApi extends ApiClient {
  final List<Map<String, dynamic>> activities;

  _FakeActivitiesApi(this.activities);

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/activities')) {
      return {'activities': activities};
    }
    if (path.startsWith('/api/families/') && path.contains('/budget')) {
      return {
        'budget': {
          'allocated_coins': 100,
          'spent_coins': 20,
          'remaining_coins': 80,
        }
      };
    }
    if (path == '/api/me') {
      return {
        'user': {'id': 1, 'display_name': 'Parent'},
        'families': [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ],
      };
    }
    return {};
  }
}

Widget _wrap(Widget child, AppState app, {Locale locale = const Locale('en'), TextScaler? textScaler}) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      locale: locale,
      theme: buildAppTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: textScaler != null ? mq.copyWith(textScaler: textScaler) : mq,
            child: Scaffold(body: child),
          );
        },
      ),
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
      'tour.seen.activities': true,
      'tour.seen.profile': true,
      'tour.seen.checklist-dismissed': true,
    });
  });

  group('P6-7: Small leftovers', () {
    testWidgets('Stats Overview: fairness value label is painted in AppColors.textPrimary',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

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
            'caregiver': 'Pablo',
            'personal_minutes': 450, // 7 h 30
            'coverage_minutes': 120, // 2 h
            'month': '2026-10',
          },
          {
            'caregiver': 'Ati',
            'personal_minutes': 120, // 2 h
            'coverage_minutes': 450, // 7 h 30
            'month': '2026-10',
          },
        ],
        'trendByMonth': [
          {'month': '2026-09', 'coins': 20, 'caregiver': 'Pablo'},
          {'month': '2026-10', 'coins': 30, 'caregiver': 'Pablo'},
        ],
        'typeSplit': [
          {'type': 'care', 'caregiver': 'Pablo', 'value': 20},
        ],
      };

      final app = AppState(api: _FakeStatsApi(mockStats))
        ..families = [
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver', 'alias': 'Pablo'}
        ]
        ..profile = {'id': 1, 'display_name': 'Pablo'};

      await tester.pumpWidget(_wrap(const StatsScreen(active: true), app));
      await tester.pumpAndSettle();

      final valueFinder = find.text('7 h 30');
      expect(valueFinder, findsAtLeastNWidgets(1));

      for (final widget in tester.widgetList<Text>(valueFinder)) {
        expect(widget.style?.color, AppColors.textPrimary);
        expect(widget.style?.fontWeight, FontWeight.w800);
        expect(widget.style?.fontSize, 13);
      }
    });

    testWidgets(
        'Tasks catalogue at 390 px width: "School or daycare drop-off" wraps to 2 lines without ellipsis',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const title = 'School or daycare drop-off';
      final api = _FakeActivitiesApi([
        {
          'id': 1,
          'title': title,
          'type': 'care',
          'is_template': true,
          'is_recurrent': true,
          'duration_minutes': 30,
          'coin_value': 10,
          'status': 'approved',
        },
        {
          'id': 2,
          'title': 'Brush teeth',
          'type': 'care',
          'is_template': true,
          'is_recurrent': false,
          'duration_minutes': 5,
          'coin_value': 2,
          'status': 'approved',
        },
      ]);

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      // In Flutter test, the default Ahem font is monospace with 1:1 square glyphs
      // (16px wide per char), so 26 chars takes 416px. A text scale of 0.75 mimics
      // real Latin proportional font metrics (e.g. Roboto/Plus Jakarta Sans) where
      // the title fits across 2 lines without ellipsis.
      await tester.pumpWidget(
        _wrap(
          const ActivitiesScreen(active: true),
          app,
          textScaler: const TextScaler.linear(0.75),
        ),
      );
      await tester.pumpAndSettle();

      final titleFinder = find.byWidgetPredicate((w) =>
          w is Text &&
          (w.textSpan?.toPlainText() ?? w.data ?? '').contains(title));
      expect(titleFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(titleFinder);
      expect(textWidget.maxLines, 2);
      expect(textWidget.overflow, TextOverflow.ellipsis);

      // Repeat icon is present
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);

      // The enclosing Row has CrossAxisAlignment.start to align repeat icon with first line
      final rowFinder = find.ancestor(of: titleFinder, matching: find.byType(Row)).first;
      final rowWidget = tester.widget<Row>(rowFinder);
      expect(rowWidget.crossAxisAlignment, CrossAxisAlignment.start);

      // RenderParagraph did not exceed maxLines (did not truncate to ellipsis)
      final renderParagraph = tester.renderObject<RenderParagraph>(titleFinder);
      expect(renderParagraph.didExceedMaxLines, isFalse);
    });
  });
}
