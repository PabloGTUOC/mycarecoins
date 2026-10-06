import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/daily_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';

class FakeRemovalApiClient extends ApiClient {
  final List<Map<String, dynamic>> activities;
  final List<String> deletedPaths = [];

  FakeRemovalApiClient({required this.activities});

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/activities')) {
      return {'activities': activities};
    }
    if (path.startsWith('/api/absences')) return {'absences': []};
    if (path.startsWith('/api/personal-time')) return {'requests': []};
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
  Future<dynamic> delete(String path, [Object? body]) async {
    deletedPaths.add(path);
    return {'success': true};
  }

  @override
  Future<dynamic> post(String path, [Object? body]) async => {};
}

Widget _wrap(Widget child, AppState app) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
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
      'tour.seen.dashboard': true,
    });
  });

  group('Removal rules helper: canRemoveActivity', () {
    test('coverage cards can never be removed on their own', () {
      final app = AppState(api: FakeRemovalApiClient(activities: []))
        ..profile = {'id': 1};

      final coverage = {
        'id': 1,
        'type': 'coverage',
        'category': 'care',
        'assigned_to': 1,
      };
      expect(canRemoveActivity(coverage, app), isFalse);
    });

    test('another person’s self card cannot be removed', () {
      final app = AppState(api: FakeRemovalApiClient(activities: []))
        ..profile = {'id': 1};

      final otherSelf = {
        'id': 2,
        'type': 'sport',
        'category': 'self',
        'assigned_to': 2,
      };
      expect(canRemoveActivity(otherSelf, app), isFalse);
    });

    test('my own self card can be removed', () {
      final app = AppState(api: FakeRemovalApiClient(activities: []))
        ..profile = {'id': 1};

      final mySelf = {
        'id': 3,
        'type': 'sport',
        'category': 'self',
        'assigned_to': 1,
      };
      expect(canRemoveActivity(mySelf, app), isTrue);
    });

    test('normal care activities can be removed', () {
      final app = AppState(api: FakeRemovalApiClient(activities: []))
        ..profile = {'id': 1};

      final care = {
        'id': 4,
        'type': 'care',
        'category': 'care',
        'assigned_to': 1,
      };
      expect(canRemoveActivity(care, app), isTrue);
    });
  });

  group('DailyScreen removal rules in narrow layout', () {
    testWidgets(
        'coverage card and another person self card have no Dismissible; my own self card and normal care card do',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final activities = [
        {
          'id': 101,
          'title': 'Coverage Shift',
          'type': 'coverage',
          'category': 'care',
          'status': 'approved',
          'starts_at': '2026-10-06T08:00:00Z',
          'duration_minutes': 60,
          'assigned_to': 1,
        },
        {
          'id': 102,
          'title': 'Other Personal Time',
          'type': 'sport',
          'category': 'self',
          'status': 'approved',
          'starts_at': '2026-10-06T10:00:00Z',
          'duration_minutes': 60,
          'assigned_to': 2,
        },
        {
          'id': 103,
          'title': 'My Personal Time',
          'type': 'sport',
          'category': 'self',
          'status': 'approved',
          'starts_at': '2026-10-06T12:00:00Z',
          'duration_minutes': 60,
          'assigned_to': 1,
        },
        {
          'id': 104,
          'title': 'Care Task',
          'type': 'care',
          'category': 'care',
          'status': 'approved',
          'starts_at': '2026-10-06T14:00:00Z',
          'duration_minutes': 60,
          'assigned_to': 1,
        },
      ];

      final api = FakeRemovalApiClient(activities: activities);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(const DailyScreen(date: '2026-10-06'), app));
      await tester.pumpAndSettle();

      // All 4 activities are rendered on the timeline
      expect(find.text('Coverage Shift'), findsOneWidget);
      expect(find.text('Other Personal Time'), findsOneWidget);
      expect(find.text('My Personal Time'), findsOneWidget);
      expect(find.text('Care Task'), findsOneWidget);

      // (1) Coverage card has NO Dismissible
      expect(find.byKey(const ValueKey('act-101')), findsNothing);
      expect(
        find.ancestor(
            of: find.text('Coverage Shift'), matching: find.byType(Dismissible)),
        findsNothing,
      );

      // (2) Another person's self card has NO Dismissible
      expect(find.byKey(const ValueKey('act-102')), findsNothing);
      expect(
        find.ancestor(
            of: find.text('Other Personal Time'), matching: find.byType(Dismissible)),
        findsNothing,
      );

      // (3) My own self card HAS Dismissible
      expect(find.byKey(const ValueKey('act-103')), findsOneWidget);
      expect(
        find.ancestor(
            of: find.text('My Personal Time'), matching: find.byType(Dismissible)),
        findsOneWidget,
      );

      // (4) Normal care card HAS Dismissible
      expect(find.byKey(const ValueKey('act-104')), findsOneWidget);
      expect(
        find.ancestor(
            of: find.text('Care Task'), matching: find.byType(Dismissible)),
        findsOneWidget,
      );
    });
  });

  group('DailyScreen removal rules in wide layout', () {
    testWidgets('coverage and other self chips are not draggable, mine and care are',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final activities = [
        {
          'id': 201,
          'title': 'Wide Coverage',
          'type': 'coverage',
          'category': 'care',
          'status': 'approved',
          'starts_at': '2026-10-06T08:00:00Z',
          'duration_minutes': 60,
          'assigned_to': 1,
        },
        {
          'id': 202,
          'title': 'Wide Other Self',
          'type': 'sport',
          'category': 'self',
          'status': 'approved',
          'starts_at': '2026-10-06T10:00:00Z',
          'duration_minutes': 60,
          'assigned_to': 2,
        },
        {
          'id': 203,
          'title': 'Wide My Self',
          'type': 'sport',
          'category': 'self',
          'status': 'approved',
          'starts_at': '2026-10-06T12:00:00Z',
          'duration_minutes': 60,
          'assigned_to': 1,
        },
        {
          'id': 204,
          'title': 'Wide Care',
          'type': 'care',
          'category': 'care',
          'status': 'approved',
          'starts_at': '2026-10-06T14:00:00Z',
          'duration_minutes': 60,
          'assigned_to': 1,
        },
      ];

      final api = FakeRemovalApiClient(activities: activities);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(const DailyScreen(date: '2026-10-06'), app));
      await tester.pumpAndSettle();

      // Coverage chip: no Draggable ancestor
      expect(
        find.ancestor(
          of: find.text('Wide Coverage'),
          matching: find.byWidgetPredicate(
              (w) => w is Draggable || w is LongPressDraggable),
        ),
        findsNothing,
      );

      // Other person's self chip: no Draggable ancestor
      expect(
        find.ancestor(
          of: find.text('Wide Other Self'),
          matching: find.byWidgetPredicate(
              (w) => w is Draggable || w is LongPressDraggable),
        ),
        findsNothing,
      );

      // My own self chip: HAS Draggable ancestor
      expect(
        find.ancestor(
          of: find.text('Wide My Self'),
          matching: find.byWidgetPredicate(
              (w) => w is Draggable || w is LongPressDraggable),
        ),
        findsOneWidget,
      );

      // Care chip: HAS Draggable ancestor
      expect(
        find.ancestor(
          of: find.text('Wide Care'),
          matching: find.byWidgetPredicate(
              (w) => w is Draggable || w is LongPressDraggable),
        ),
        findsOneWidget,
      );
    });
  });

  group('Personal time with counterpart removal confirmation', () {
    testWidgets(
        'shows counterpart cancellation and sweetener warning dialog, cancels on dismiss',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final activities = [
        {
          'id': 301,
          'title': 'My Yoga with Coverage',
          'type': 'sport',
          'category': 'self',
          'status': 'approved',
          'starts_at': '2026-10-06T12:00:00Z',
          'duration_minutes': 60,
          'assigned_to': 1,
          'counterpart_activity_id': 302,
        },
      ];

      final api = FakeRemovalApiClient(activities: activities);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(const DailyScreen(date: '2026-10-06'), app));
      await tester.pumpAndSettle();

      // Swipe to trigger removal flow
      await tester.drag(find.text('My Yoga with Coverage'), const Offset(-300, 0));
      await tester.pumpAndSettle();

      // Confirmation dialog must appear with the counterpart cancellation warning string
      expect(
        find.text(
            'Cancelling this also cancels the other person\'s coverage shift, and any sweetener comes back to you.'),
        findsOneWidget,
      );

      // Tapping Cancel dismisses dialog without deleting
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(api.deletedPaths, isEmpty);

      // Swipe again and confirm
      await tester.drag(find.text('My Yoga with Coverage'), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Cancelling this also cancels the other person\'s coverage shift, and any sweetener comes back to you.'),
        findsOneWidget,
      );

      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Remove')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));

      expect(api.deletedPaths, contains('/api/activities/301'));
    });
  });
}
