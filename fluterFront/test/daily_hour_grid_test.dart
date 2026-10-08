import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/daily_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/theme/app_theme.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

class FakeGridApiClient extends ApiClient {
  List<Map<String, dynamic>> activities;
  List<Map<String, dynamic>> absences;
  List<Map<String, dynamic>> requests;
  List<Map<String, dynamic>> members;

  FakeGridApiClient({
    this.activities = const [],
    this.absences = const [],
    this.requests = const [],
    this.members = const [],
  });

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/activities')) {
      return {'activities': activities};
    }
    if (path.startsWith('/api/absences')) {
      return {'absences': absences};
    }
    if (path.startsWith('/api/personal-time')) {
      return {'requests': requests};
    }
    if (path.startsWith('/api/dashboard/')) {
      return {
        'members': members,
        'calendar': [],
        'objectsOfCare': [],
      };
    }
    if (path.startsWith('/api/marketplace/rewards/')) {
      return {'rewards': [], 'claimed': []};
    }
    if (path == '/api/me') {
      return {
        'user': {'id': 1, 'display_name': 'Me'},
        'families': [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ],
      };
    }
    return {};
  }

  @override
  Future<dynamic> post(String path, [Object? body]) async {
    return {'success': true};
  }

  @override
  Future<dynamic> delete(String path, [Object? body]) async {
    return {'success': true};
  }
}

Widget _wrap(Widget child, AppState app) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child is DailyScreen ? child : Center(child: child),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tour.seen.welcome': true,
      'tour.seen.daily': true,
      'tour.seen.dashboard': true,
      'tour.seen.checklist-dismissed': true,
    });
  });

  group('P2-7: Today hour grid on phones', () {
    testWidgets('the phone layout renders the grid and not the card list',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeGridApiClient();
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const DailyScreen(date: '2026-10-06'), app));
      await tester.pumpAndSettle();

      // Card list (ListView) must be gone
      expect(find.byType(ListView), findsNothing);

      // Hour grid (SingleChildScrollView) is present
      expect(find.byType(SingleChildScrollView), findsWidgets);

      // Hour lines/labels from 06:00 to 24:00 are present
      expect(find.text('06:00'), findsOneWidget);
      expect(find.text('12:00'), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);

      // T1 week strip is preserved; phones add through the tray (no FAB).
      expect(find.byType(WeekStrip), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('a 30-minute and a 90-minute block have proportional heights',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeGridApiClient(
        activities: [
          {
            'id': 101,
            'title': 'Quick 30m',
            'type': 'care',
            'category': 'care',
            'status': 'approved',
            'starts_at': '2026-10-06T08:00:00Z',
            'duration_minutes': 30,
            'assigned_to': 1,
          },
          {
            'id': 102,
            'title': 'Long 90m',
            'type': 'care',
            'category': 'care',
            'status': 'approved',
            'starts_at': '2026-10-06T10:00:00Z',
            'duration_minutes': 90,
            'assigned_to': 1,
          },
        ],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const DailyScreen(date: '2026-10-06'), app));
      await tester.pumpAndSettle();

      final pos30 = find.ancestor(
        of: find.text('Quick 30m'),
        matching: find.byType(Positioned),
      ).first;
      final pos90 = find.ancestor(
        of: find.text('Long 90m'),
        matching: find.byType(Positioned),
      ).first;

      final rect30 = tester.getRect(pos30);
      final rect90 = tester.getRect(pos90);

      // 30 min duration clamps to min readable height (52 dp)
      expect(rect30.height, equals(52.0));
      // 90 min duration is 1.5 hours * 64 dp/hour = 96 dp
      expect(rect90.height, equals(96.0));
    });

    testWidgets('two overlapping blocks share the width side by side',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeGridApiClient(
        activities: [
          {
            'id': 101,
            'title': 'Overlap A',
            'type': 'care',
            'category': 'care',
            'status': 'approved',
            'starts_at': '2026-10-06T09:00:00Z',
            'duration_minutes': 60,
            'assigned_to': 1,
          },
          {
            'id': 102,
            'title': 'Overlap B',
            'type': 'care',
            'category': 'care',
            'status': 'approved',
            'starts_at': '2026-10-06T09:30:00Z',
            'duration_minutes': 60,
            'assigned_to': 2,
          },
        ],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const DailyScreen(date: '2026-10-06'), app));
      await tester.pumpAndSettle();

      final posA = find.ancestor(
        of: find.text('Overlap A'),
        matching: find.byType(Positioned),
      ).first;
      final posB = find.ancestor(
        of: find.text('Overlap B'),
        matching: find.byType(Positioned),
      ).first;

      final rectA = tester.getRect(posA);
      final rectB = tester.getRect(posB);

      // Overlapping blocks share the width equally
      expect((rectA.width - rectB.width).abs(), lessThan(1.0));
      // Overlapping blocks sit side by side (left coordinates differ)
      expect(rectA.left, isNot(equals(rectB.left)));
      expect(rectB.left, greaterThanOrEqualTo(rectA.right - 1.0));
    });

    testWidgets('NOW line present on today and absent on other days',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeGridApiClient();
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      final fixedNow = DateTime(2026, 10, 6, 12, 0);

      // 1. On today (date matches now at 12:00)
      await tester.pumpWidget(_wrap(
        DailyScreen(date: '2026-10-06', now: fixedNow),
        app,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('now-line-dot')), findsOneWidget);

      // 2. On other days (yesterday compared to fixedNow)
      await tester.pumpWidget(_wrap(
        DailyScreen(date: '2026-10-05', now: fixedNow),
        app,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('now-line-dot')), findsNothing);
    });

    testWidgets(
        'Needs you collapsed line text with 2 items and expands in place',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeGridApiClient(
        activities: [
          {
            'id': 101,
            'title': 'Bath time',
            'status': 'pending_validation',
            'assigned_to': 2,
            'assigned_to_name': 'Ben',
            'coin_value': 20,
            'duration_minutes': 30,
            'starts_at': '2026-10-06T18:00:00Z',
          },
        ],
        requests: [
          {
            'id': 201,
            'title': 'Friday shift',
            'type': 'meditation',
            'status': 'pending',
            'requester_id': 2,
            'requester_name': 'Ana',
            'requested_of': 1,
            'sweetener_coins': 10,
            'starts_at': '2026-10-09T18:00:00Z',
            'ends_at': '2026-10-09T19:00:00Z',
          },
        ],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const DailyScreen(date: '2026-10-06'), app));
      await tester.pumpAndSettle();

      // Folded one-line summary: "{first}, and 1 more" without numeric badge
      expect(
        find.text('Validate "Bath time" · Ben, and 1 more'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
      // Items inside are not shown yet
      expect(find.text('Ana asks you to cover "Friday shift"'), findsNothing);

      // Tap expand chevron
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();

      // Expanded list shows Needs you header and both action items
      expect(find.text('Needs you'), findsOneWidget);
      expect(find.text('Validate "Bath time" · Ben'), findsOneWidget);
      expect(find.text('Ana asks you to cover "Friday shift"'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
    });

    testWidgets('absence band renders across the grid with label',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeGridApiClient(
        absences: [
          {
            'user_id': 2,
            'user_name': 'Ati',
            'start_time': '2026-10-06T10:00:00Z',
            'end_time': '2026-10-06T14:00:00Z',
          },
        ],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(_wrap(const DailyScreen(date: '2026-10-06'), app));
      await tester.pumpAndSettle();

      // Absence label is visible on the grid band
      expect(find.text('Ati away'), findsOneWidget);

      // T4 semantics label is present on the absence band
      final semNode = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Ati away')).first,
      );
      expect(semNode.label, contains('Ati away'));

      semantics.dispose();
    });

    testWidgets('dashed request block renders at its scheduled time',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeGridApiClient(
        requests: [
          {
            'id': 301,
            'title': 'Yoga Session',
            'type': 'sport',
            'status': 'pending',
            'requester_id': 2,
            'requester_name': 'Ana',
            'starts_at': '2026-10-06T15:00:00Z',
            'ends_at': '2026-10-06T16:00:00Z',
          },
        ],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(_wrap(const DailyScreen(date: '2026-10-06'), app));
      await tester.pumpAndSettle();

      // Dashed request block displays title, requester, and status
      expect(find.text('Yoga Session'), findsOneWidget);
      expect(find.textContaining('Ana'), findsWidgets);

      // Has dashed border CustomPaint
      expect(
        find.byWidgetPredicate((w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_DashedBorderPainter'),
        findsWidgets,
      );

      // T4 semantics label is present
      final semNode = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Yoga Session')).first,
      );
      expect(semNode.label, contains('Yoga Session'));
      expect(semNode.label, contains('Ana'));

      semantics.dispose();
    });

    testWidgets(
        'at 120 dp wide and 150 dp tall the title is not truncated to fewer than 6 characters and no AssigneeBadge/pill has zero-width text',
        (tester) async {
      final activity = {
        'id': 101,
        'title': 'Personal Time for Doctor',
        'type': 'care',
        'category': 'care',
        'status': 'pending_validation',
        'starts_at': '2026-10-06T10:00:00Z',
        'duration_minutes': 90,
        'assigned_to': 2,
        'assigned_to_name': 'Ben',
        'coin_value': 20,
      };

      final api = FakeGridApiClient();
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 120,
          height: 150,
          child: DayActivityBlock(
            activity: activity,
            onValidate: (_) {},
            onDelegate: (_) {},
            onTakeOver: (_) {},
          ),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      // Title is rendered across lines, not truncated to fewer than 6 characters
      final titleFinder = find.textContaining('Personal Time');
      expect(titleFinder, findsOneWidget);
      final titleWidget = tester.widget<Text>(titleFinder);
      expect(titleWidget.textSpan!.toPlainText(), contains('Personal Time'));
      expect(tester.getSize(titleFinder).width, greaterThan(40.0));

      // AssigneeBadge is present and text width is > 0
      expect(find.byType(AssigneeBadge), findsOneWidget);
      final badgeTextFinder = find.descendant(
        of: find.byType(AssigneeBadge),
        matching: find.byType(Text),
      );
      expect(badgeTextFinder, findsOneWidget);
      expect(tester.getSize(badgeTextFinder).width, greaterThan(0.0));

      // Coin pill is present and text width is > 0
      final coinFinder = find.text('20 cc');
      expect(coinFinder, findsOneWidget);
      expect(tester.getSize(coinFinder).width, greaterThan(0.0));

      // Action pill is present and text width is > 0
      final actionPillFinder = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_ActivityAction',
      );
      expect(actionPillFinder, findsOneWidget);
      final actionTextFinder = find.descendant(
        of: actionPillFinder,
        matching: find.byType(Text),
      );
      expect(actionTextFinder, findsOneWidget);
      expect(tester.getSize(actionTextFinder).width, greaterThan(0.0));
    });

    testWidgets('at 40 dp tall only the title renders', (tester) async {
      final activity = {
        'id': 101,
        'title': 'Bath time and reading',
        'type': 'care',
        'category': 'care',
        'status': 'pending_validation',
        'starts_at': '2026-10-06T10:00:00Z',
        'duration_minutes': 30,
        'assigned_to': 2,
        'assigned_to_name': 'Ben',
        'coin_value': 20,
      };

      final api = FakeGridApiClient();
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 120,
          height: 40,
          child: DayActivityBlock(
            activity: activity,
            onValidate: (_) {},
          ),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      // Only the title renders
      expect(find.textContaining('Bath time'), findsOneWidget);
      // Meta row (badge, coins) and action pill do NOT render
      expect(find.byType(AssigneeBadge), findsNothing);
      expect(find.text('20 cc'), findsNothing);
      expect(find.text('Validate'), findsNothing);
      expect(find.byType(AvatarCircle), findsNothing);
    });

    testWidgets('category fills per type', (tester) async {
      final api = FakeGridApiClient();
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      // 1. Care: successSoft fill + successInk text
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 150,
          height: 80,
          child: DayActivityBlock(
            activity: {
              'id': 1,
              'title': 'Care task',
              'type': 'care',
              'category': 'care',
              'status': 'approved',
            },
          ),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      final careContainer = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(DayActivityBlock),
              matching: find.byType(Container),
            )
            .first,
      );
      final careDeco = careContainer.decoration as BoxDecoration;
      expect(careDeco.color, equals(AppColors.successSoft));
      final careText = tester.widget<Text>(find.textContaining('Care task'));
      expect(careText.style?.color, equals(AppColors.successInk));

      // 2. Household: warningSoft fill + warningInk text
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 150,
          height: 80,
          child: DayActivityBlock(
            activity: {
              'id': 2,
              'title': 'Dishes',
              'type': 'household',
              'category': 'household',
              'status': 'approved',
            },
          ),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      final houseContainer = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(DayActivityBlock),
              matching: find.byType(Container),
            )
            .first,
      );
      final houseDeco = houseContainer.decoration as BoxDecoration;
      expect(houseDeco.color, equals(AppColors.warningSoft));
      final houseText = tester.widget<Text>(find.textContaining('Dishes'));
      expect(houseText.style?.color, equals(AppColors.warningInk));

      // 3. Coverage: primarySoft fill + primaryInk text
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 150,
          height: 80,
          child: DayActivityBlock(
            activity: {
              'id': 3,
              'title': 'Coverage block',
              'type': 'coverage',
              'category': 'care',
              'status': 'approved',
            },
          ),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      final covContainer = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(DayActivityBlock),
              matching: find.byType(Container),
            )
            .first,
      );
      final covDeco = covContainer.decoration as BoxDecoration;
      expect(covDeco.color, equals(AppColors.primarySoft));
      final covText =
          tester.widget<Text>(find.textContaining('Coverage block'));
      expect(covText.style?.color, equals(AppColors.primaryInk));

      // 4. Personal time: surface fill + 1px inputBorder outline + textPrimary text
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 150,
          height: 80,
          child: DayActivityBlock(
            activity: {
              'id': 4,
              'title': 'Doctor visit',
              'type': 'doctor',
              'category': 'self',
              'status': 'approved',
              'assigned_to': 1,
            },
          ),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      final selfContainer = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(DayActivityBlock),
              matching: find.byType(Container),
            )
            .first,
      );
      final selfDeco = selfContainer.decoration as BoxDecoration;
      expect(selfDeco.color, equals(AppColors.surface));
      expect(
        selfDeco.border,
        equals(Border.all(color: AppColors.inputBorder, width: 1.0)),
      );
      final selfText = tester.widget<Text>(find.textContaining('Doctor visit'));
      expect(selfText.style?.color, equals(AppColors.textPrimary));

      // 5. Completed care: successStrong fill + white text
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 150,
          height: 80,
          child: DayActivityBlock(
            activity: {
              'id': 5,
              'title': 'Completed Care',
              'type': 'care',
              'category': 'care',
              'status': 'completed',
            },
          ),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      final doneCareContainer = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(DayActivityBlock),
              matching: find.byType(Container),
            )
            .first,
      );
      final doneCareDeco = doneCareContainer.decoration as BoxDecoration;
      expect(doneCareDeco.color, equals(AppColors.successStrong));
      final doneCareText =
          tester.widget<Text>(find.textContaining('Completed Care'));
      expect(doneCareText.style?.color, equals(Colors.white));

      // 6. Completed household: warningStrong fill + white text
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 150,
          height: 80,
          child: DayActivityBlock(
            activity: {
              'id': 6,
              'title': 'Completed Chores',
              'type': 'household',
              'category': 'household',
              'status': 'completed',
            },
          ),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      final doneHouseContainer = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(DayActivityBlock),
              matching: find.byType(Container),
            )
            .first,
      );
      final doneHouseDeco = doneHouseContainer.decoration as BoxDecoration;
      expect(doneHouseDeco.color, equals(AppColors.warningStrong));
      final doneHouseText =
          tester.widget<Text>(find.textContaining('Completed Chores'));
      expect(doneHouseText.style?.color, equals(Colors.white));
    });

    testWidgets('width < 120 hides emoji and renders 20 dp avatar circle',
        (tester) async {
      final api = FakeGridApiClient();
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      // 1. Own activity: initial 'P' with primarySoft and primary border
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 110,
          height: 80,
          child: DayActivityBlock(
            activity: {
              'id': 7,
              'title': 'My Care Shift',
              'type': 'care',
              'category': 'care',
              'status': 'approved',
              'assigned_to': 1,
            },
          ),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      // Emoji ❤️ is hidden
      expect(find.text('❤️'), findsNothing);
      // AssigneeBadge is replaced
      expect(find.byType(AssigneeBadge), findsNothing);
      // User's own initial ('P' for Parent) is displayed
      expect(find.text('P'), findsOneWidget);

      final circleFinder = find
          .ancestor(
            of: find.text('P'),
            matching: find.byType(Container),
          )
          .first;
      final circleContainer = tester.widget<Container>(circleFinder);
      final circleDeco = circleContainer.decoration as BoxDecoration;
      expect(circleDeco.shape, equals(BoxShape.circle));
      expect(circleDeco.color, equals(AppColors.primarySoft));
      expect(
        circleDeco.border,
        equals(Border.all(color: AppColors.primary, width: 1.0)),
      );

      // 2. Another user's activity: initial 'B' with bg and border
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 110,
          height: 80,
          child: DayActivityBlock(
            activity: {
              'id': 8,
              'title': 'Ben Care Shift',
              'type': 'care',
              'category': 'care',
              'status': 'approved',
              'assigned_to': 2,
              'assigned_to_name': 'Ben',
            },
          ),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      expect(find.text('B'), findsOneWidget);
      final otherCircleFinder = find
          .ancestor(
            of: find.text('B'),
            matching: find.byType(Container),
          )
          .first;
      final otherCircleContainer =
          tester.widget<Container>(otherCircleFinder);
      final otherCircleDeco =
          otherCircleContainer.decoration as BoxDecoration;
      expect(otherCircleDeco.shape, equals(BoxShape.circle));
      expect(otherCircleDeco.color, equals(AppColors.bg));
      expect(
        otherCircleDeco.border,
        equals(Border.all(color: AppColors.border, width: 1.0)),
      );
    });
  });
}

