import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/daily_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/theme/app_theme.dart';

class FakeDailyApiClient extends ApiClient {
  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/activities')) {
      return {'activities': []};
    }
    if (path.startsWith('/api/absences')) {
      return {'absences': []};
    }
    if (path.startsWith('/api/personal-time')) {
      return {'requests': []};
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

  @override
  Future<dynamic> post(String path, [Object? body]) async {
    return {};
  }
}

Widget _app(Widget child, {AppState? app}) {
  final content = MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
  if (app != null) {
    return ChangeNotifierProvider<AppState>.value(
      value: app,
      child: content,
    );
  }
  return content;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('T1: WeekStrip unit and standalone tests', () {
    test('weekDaysFor returns Monday to Sunday for the week containing selected day', () {
      // 2026-10-06 is a Tuesday
      final selected = DateTime(2026, 10, 6);
      final days = WeekStrip.weekDaysFor(selected);

      expect(days.length, 7);
      expect(days[0], DateTime(2026, 10, 5)); // Monday
      expect(days[1], DateTime(2026, 10, 6)); // Tuesday
      expect(days[2], DateTime(2026, 10, 7)); // Wednesday
      expect(days[3], DateTime(2026, 10, 8)); // Thursday
      expect(days[4], DateTime(2026, 10, 9)); // Friday
      expect(days[5], DateTime(2026, 10, 10)); // Saturday
      expect(days[6], DateTime(2026, 10, 11)); // Sunday
    });

    testWidgets('renders seven day chips with initials and numbers', (tester) async {
      tester.view.physicalSize = const Size(412, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final selectedDay = DateTime(2026, 10, 6); // Tuesday
      DateTime? chosenDay;

      await tester.pumpWidget(
        _app(
          WeekStrip(
            selectedDay: selectedDay,
            onSelectDay: (d) => chosenDay = d,
            onWeekChange: (_) {},
            today: DateTime(2026, 10, 6),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chipFinder = find.byType(WeekDayChip);
      expect(chipFinder, findsNWidgets(7));

      // Day numbers 5 to 11
      for (int d = 5; d <= 11; d++) {
        expect(find.text('$d'), findsOneWidget);
      }

      // Weekday initials
      expect(find.text('M'), findsOneWidget); // Monday
      expect(find.text('T'), findsNWidgets(2)); // Tuesday & Thursday
      expect(find.text('W'), findsOneWidget); // Wednesday
      expect(find.text('F'), findsOneWidget); // Friday
      expect(find.text('S'), findsNWidgets(2)); // Saturday & Sunday

      // Tapping a chip calls onSelectDay
      await tester.tap(find.text('8'));
      await tester.pumpAndSettle();
      expect(chosenDay, DateTime(2026, 10, 8));
    });

    testWidgets('each chip is at least 44x44 dp', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final selectedDay = DateTime(2026, 10, 6);

      await tester.pumpWidget(
        _app(
          WeekStrip(
            selectedDay: selectedDay,
            onSelectDay: (_) {},
            onWeekChange: (_) {},
            today: DateTime(2026, 10, 6),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chips = tester.widgetList<WeekDayChip>(find.byType(WeekDayChip));
      expect(chips.length, 7);

      for (final element in find.byType(WeekDayChip).evaluate()) {
        final size = tester.getSize(find.byWidget(element.widget));
        expect(size.width, greaterThanOrEqualTo(44.0));
        expect(size.height, greaterThanOrEqualTo(44.0));
      }
    });

    testWidgets('selected day is filled with AppColors.primary and white text', (tester) async {
      final selectedDay = DateTime(2026, 10, 6); // Tuesday

      await tester.pumpWidget(
        _app(
          WeekStrip(
            selectedDay: selectedDay,
            onSelectDay: (_) {},
            onWeekChange: (_) {},
            today: DateTime(2026, 10, 6),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find Tuesday chip (day 6)
      final tuesdayChipFinder = find.ancestor(
        of: find.text('6'),
        matching: find.byType(WeekDayChip),
      );
      expect(tuesdayChipFinder, findsOneWidget);

      final material = tester.widget<Material>(
        find.descendant(of: tuesdayChipFinder, matching: find.byType(Material)),
      );
      expect(material.color, AppColors.primary);

      final numText = tester.widget<Text>(find.text('6'));
      expect(numText.style?.color, Colors.white);

      // Unselected chip (Monday, day 5)
      final mondayChipFinder = find.ancestor(
        of: find.text('5'),
        matching: find.byType(WeekDayChip),
      );
      final mondayMaterial = tester.widget<Material>(
        find.descendant(of: mondayChipFinder, matching: find.byType(Material)),
      );
      expect(mondayMaterial.color, Colors.transparent);

      final mondayNumText = tester.widget<Text>(find.text('5'));
      expect(mondayNumText.style?.color, AppColors.textSecondary);
    });

    testWidgets('today is marked with a small dot and other days have transparent dot', (tester) async {
      final selectedDay = DateTime(2026, 10, 6);
      final today = DateTime(2026, 10, 7); // Wednesday is today, not selected

      await tester.pumpWidget(
        _app(
          WeekStrip(
            selectedDay: selectedDay,
            onSelectDay: (_) {},
            onWeekChange: (_) {},
            today: today,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Wednesday chip has visible dot in AppColors.primary
      final wednesdayChip = find.ancestor(
        of: find.text('7'),
        matching: find.byType(WeekDayChip),
      );
      final dotContainer = tester.widget<Container>(
        find.descendant(
          of: wednesdayChip,
          matching: find.byWidgetPredicate(
            (w) => w is Container && (w.decoration as BoxDecoration?)?.shape == BoxShape.circle,
          ),
        ),
      );
      final decor = dotContainer.decoration as BoxDecoration;
      expect(decor.color, AppColors.primary);

      // Thursday chip (not today) has transparent dot
      final thursdayChip = find.ancestor(
        of: find.text('8'),
        matching: find.byType(WeekDayChip),
      );
      final thurDotContainer = tester.widget<Container>(
        find.descendant(
          of: thursdayChip,
          matching: find.byWidgetPredicate(
            (w) => w is Container && (w.decoration as BoxDecoration?)?.shape == BoxShape.circle,
          ),
        ),
      );
      final thurDecor = thurDotContainer.decoration as BoxDecoration;
      expect(thurDecor.color, Colors.transparent);
    });

    testWidgets('semantics wrap each chip with button, selected, and full localized date', (tester) async {
      final selectedDay = DateTime(2026, 10, 6);

      await tester.pumpWidget(
        _app(
          WeekStrip(
            selectedDay: selectedDay,
            onSelectDay: (_) {},
            onWeekChange: (_) {},
            today: selectedDay,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final expectedLabel = DateFormat.yMMMMEEEEd('en').format(selectedDay);

      final selectedChip = find.ancestor(
        of: find.text('6'),
        matching: find.byType(WeekDayChip),
      );
      final semanticsWidget = tester.widget<Semantics>(
        find.descendant(of: selectedChip, matching: find.byType(Semantics)).first,
      );

      expect(semanticsWidget.properties.button, isTrue);
      expect(semanticsWidget.properties.selected, isTrue);
      expect(semanticsWidget.properties.label, expectedLabel);

      // Monday (unselected)
      final unselectedDay = DateTime(2026, 10, 5);
      final unselectedLabel = DateFormat.yMMMMEEEEd('en').format(unselectedDay);
      final unselectedChip = find.ancestor(
        of: find.text('5'),
        matching: find.byType(WeekDayChip),
      );
      final unselectedSemantics = tester.widget<Semantics>(
        find.descendant(of: unselectedChip, matching: find.byType(Semantics)).first,
      );

      expect(unselectedSemantics.properties.button, isTrue);
      expect(unselectedSemantics.properties.selected, isFalse);
      expect(unselectedSemantics.properties.label, unselectedLabel);
    });

    testWidgets('horizontal fling on strip moves week backward or forward', (tester) async {
      int? weekDelta;

      await tester.pumpWidget(
        _app(
          WeekStrip(
            selectedDay: DateTime(2026, 10, 6),
            onSelectDay: (_) {},
            onWeekChange: (d) => weekDelta = d,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fling left (drag towards left, negative velocity < -300) -> next week (+1)
      await tester.fling(find.byType(WeekStrip), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(weekDelta, 1);

      weekDelta = null;

      // Fling right (drag towards right, positive velocity > 300) -> previous week (-1)
      await tester.fling(find.byType(WeekStrip), const Offset(400, 0), 1000);
      await tester.pumpAndSettle();
      expect(weekDelta, -1);

      weekDelta = null;

      // Slow drag below velocity threshold (300) does not change week
      await tester.drag(find.byType(WeekStrip), const Offset(50, 0));
      await tester.pumpAndSettle();
      expect(weekDelta, isNull);
    });
  });

  group('T1: DailyScreen integration tests', () {
    testWidgets('horizontal drag on list area does not change the selected date', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeApi = FakeDailyApiClient();
      final app = AppState(api: fakeApi)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_app(const DailyScreen(date: '2026-10-06'), app: app));
      await tester.pumpAndSettle();

      // Initial date in AppBar is Tue, Oct 6
      expect(find.text('Tue, Oct 6'), findsOneWidget);

      // Perform a strong horizontal drag on the grid scroll area
      final listFinder = find.byType(SingleChildScrollView);
      expect(listFinder, findsWidgets);

      await tester.fling(listFinder.first, const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      // The selected date MUST NOT have changed (remains Tue, Oct 6)
      expect(find.text('Tue, Oct 6'), findsOneWidget);

      await tester.fling(listFinder.first, const Offset(400, 0), 1000);
      await tester.pumpAndSettle();

      expect(find.text('Tue, Oct 6'), findsOneWidget);
    });

    testWidgets('tapping a chip in WeekStrip changes the selected date', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeApi = FakeDailyApiClient();
      final app = AppState(api: fakeApi)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_app(const DailyScreen(date: '2026-10-06'), app: app));
      await tester.pumpAndSettle();

      expect(find.text('Tue, Oct 6'), findsOneWidget);

      // Tap day 8 (Thursday) in the WeekStrip
      final day8Chip = find.ancestor(
        of: find.text('8'),
        matching: find.byType(WeekDayChip),
      );
      expect(day8Chip, findsOneWidget);

      await tester.tap(day8Chip);
      await tester.pumpAndSettle();

      // AppBar now shows Thu, Oct 8
      expect(find.text('Thu, Oct 8'), findsOneWidget);
      expect(find.text('Tue, Oct 6'), findsNothing);
    });

    testWidgets('flinging WeekStrip in DailyScreen moves week forward and backward', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeApi = FakeDailyApiClient();
      final app = AppState(api: fakeApi)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_app(const DailyScreen(date: '2026-10-06'), app: app));
      await tester.pumpAndSettle();

      expect(find.text('Tue, Oct 6'), findsOneWidget);

      // Fling strip left (advance 1 week forward)
      await tester.fling(find.byType(WeekStrip), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      // Selected day is now Tue, Oct 13 (same weekday, +7 days)
      expect(find.text('Tue, Oct 13'), findsOneWidget);
      expect(find.text('13'), findsOneWidget);

      // Fling strip right (move 1 week backward)
      await tester.fling(find.byType(WeekStrip), const Offset(400, 0), 1000);
      await tester.pumpAndSettle();

      // Selected day is back to Tue, Oct 6
      expect(find.text('Tue, Oct 6'), findsOneWidget);
    });
  });
}
