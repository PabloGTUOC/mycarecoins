import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/daily_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

class FakeStatesApiClient extends ApiClient {
  List<Map<String, dynamic>> activities;
  List<Map<String, dynamic>> absences;
  List<Map<String, dynamic>> requests;
  List<Map<String, dynamic>> members;

  bool shouldFailGetActivities = false;
  Completer<dynamic>? activitiesGetCompleter;

  final List<String> getCalls = [];
  final List<String> postCalls = [];
  final List<String> patchCalls = [];
  final List<String> deleteCalls = [];

  FakeStatesApiClient({
    this.activities = const [],
    this.absences = const [],
    this.requests = const [],
    this.members = const [],
  });

  @override
  Future<dynamic> get(String path) async {
    getCalls.add(path);
    if (path.startsWith('/api/activities')) {
      if (activitiesGetCompleter != null) {
        await activitiesGetCompleter!.future;
      }
      if (shouldFailGetActivities) {
        throw Exception('Network offline');
      }
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
    postCalls.add(path);
    if (path.contains('/validate')) {
      return {'success': true};
    }
    if (path.contains('/schedule')) {
      return {
        'activity': {
          'id': 999,
          'title': 'New Scheduled',
          'category': 'care',
          'type': 'care',
          'status': 'approved',
          'assigned_to': 1,
          'starts_at': (body is Map ? body['startsAt'] : null)?.toString(),
          'duration_minutes': 30,
          'coin_value': 10,
        },
        'warning': null,
      };
    }
    return {'success': true};
  }

  @override
  Future<dynamic> patch(String path, [Object? body]) async {
    patchCalls.add(path);
    return {'activity': {'id': 1}};
  }

  @override
  Future<dynamic> delete(String path, [Object? body]) async {
    deleteCalls.add(path);
    return {'success': true};
  }
}

void setPhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
}

Widget _wrap(Widget child, AppState app, {bool disableAnimations = false}) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, materialAppChild) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
          child: materialAppChild!,
        );
      },
      home: ScaffoldMessenger(
        child: child is DailyScreen ? child : Center(child: child),
      ),
    ),
  );
}

void main() {
  final now = DateTime(2026, 10, 8, 10, 0);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tour.seen.welcome': true,
      'tour.seen.daily': true,
      'tour.seen.dashboard': true,
      'tour.seen.checklist-dismissed': true,
    });
  });

  group('P2-10: 1. Loading skeleton', () {
    testWidgets('first load shows skeleton grid (placeholder blocks, hour lines, no spinner)',
        (tester) async {
      setPhoneSize(tester);
      final completer = Completer<dynamic>();
      final api = FakeStatesApiClient()..activitiesGetCompleter = completer;
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(DailyScreen(now: now), app, disableAnimations: true));
      // Pump initial frame before completer resolves
      await tester.pump();

      // No CircularProgressIndicator
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Skeleton placeholder blocks exist
      expect(find.byKey(const ValueKey('skeleton-block-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('skeleton-block-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('skeleton-block-2')), findsOneWidget);

      // Hour lines are rendered in skeleton
      expect(find.text('06:00'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);

      // Now resolve the load
      completer.complete({'activities': []});
      await tester.pumpAndSettle();

      // Skeleton is replaced by the day view
      expect(find.byKey(const ValueKey('skeleton-block-0')), findsNothing);
    });

    testWidgets('refreshes keep the current grid visible without flashing skeleton or spinner',
        (tester) async {
      setPhoneSize(tester);
      final act = {
        'id': 101,
        'title': 'Morning Care',
        'type': 'care',
        'category': 'care',
        'status': 'approved',
        'starts_at': '2026-10-08T09:00:00Z',
        'duration_minutes': 60,
        'assigned_to': 1,
        'coin_value': 20,
      };

      final api = FakeStatesApiClient(activities: [act]);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(DailyScreen(now: now), app, disableAnimations: true));
      await tester.pumpAndSettle();

      expect(find.text('Morning Care'), findsOneWidget);
      expect(find.byKey(const ValueKey('skeleton-block-0')), findsNothing);

      // Trigger refresh while suspending API call
      final refreshCompleter = Completer<dynamic>();
      api.activitiesGetCompleter = refreshCompleter;

      // Pull to refresh
      await tester.fling(find.text('Morning Care'), const Offset(0, 300), 1000);
      await tester.pump();

      // Grid is STILL visible, no skeleton placeholder
      expect(find.text('Morning Care'), findsOneWidget);
      expect(find.byKey(const ValueKey('skeleton-block-0')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Resolve refresh
      refreshCompleter.complete({'activities': [act]});
      await tester.pumpAndSettle();

      expect(find.text('Morning Care'), findsOneWidget);
    });
  });

  group('P2-10: 2. Empty day', () {
    testWidgets('empty day displays centered muted line and hides 0/0 done progress bar',
        (tester) async {
      setPhoneSize(tester);
      final api = FakeStatesApiClient(activities: []);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(DailyScreen(now: now), app, disableAnimations: true));
      await tester.pumpAndSettle();

      // Empty day line inside grid is displayed
      expect(
        find.text('Nothing planned. Drag a task here, or tap an hour.'),
        findsOneWidget,
      );

      // No progress indicator row (LinearProgressIndicator)
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('day with activities displays progress bar and hides empty day line',
        (tester) async {
      setPhoneSize(tester);
      final act = {
        'id': 101,
        'title': 'Prep Lunch',
        'type': 'household',
        'category': 'care',
        'status': 'completed',
        'starts_at': '2026-10-08T12:00:00Z',
        'duration_minutes': 45,
        'assigned_to': 1,
        'coin_value': 15,
      };

      final api = FakeStatesApiClient(activities: [act]);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(DailyScreen(now: now), app, disableAnimations: true));
      await tester.pumpAndSettle();

      // Empty day line is NOT shown
      expect(
        find.text('Nothing planned. Drag a task here, or tap an hour.'),
        findsNothing,
      );

      // Progress bar IS shown
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('1 / 1 done'), findsOneWidget);
    });
  });

  group('P2-10: 3. Past days', () {
    testWidgets('past day shows muted banner under week strip',
        (tester) async {
      setPhoneSize(tester);
      final api = FakeStatesApiClient(activities: []);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-07', now: now), app, disableAnimations: true));
      await tester.pumpAndSettle();

      // Banner is visible
      expect(find.text('This day has passed'), findsOneWidget);
      // A past day is read-only, so it does not invite drags or taps.
      expect(find.textContaining('Nothing planned'), findsNothing);
    });

    testWidgets('past day: tray chips are not draggable and tapping shows snackbar',
        (tester) async {
      setPhoneSize(tester);
      final template = {
        'id': 201,
        'title': 'Vacuuming',
        'type': 'household',
        'category': 'care',
        'is_template': true,
        'status': 'approved',
        'coin_value': 10,
        'duration_minutes': 30,
      };

      final api = FakeStatesApiClient(activities: [template]);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-07', now: now), app, disableAnimations: true));
      await tester.pumpAndSettle();

      final chipFinder = find.text('Vacuuming');
      expect(chipFinder, findsOneWidget);

      // Not draggable
      expect(
        find.ancestor(
          of: chipFinder,
          matching: find.byWidgetPredicate((w) => w is Draggable || w is LongPressDraggable),
        ),
        findsNothing,
      );

      // Tapping chip shows SnackBar
      await tester.tap(chipFinder);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(SnackBar), matching: find.text('This day has passed')),
        findsOneWidget,
      );
      expect(api.postCalls.isEmpty, isTrue);
    });

    testWidgets('past day: quick add on hour tap does not open sheet',
        (tester) async {
      setPhoneSize(tester);
      final template = {
        'id': 201,
        'title': 'Vacuuming',
        'type': 'household',
        'category': 'care',
        'is_template': true,
        'status': 'approved',
        'coin_value': 10,
        'duration_minutes': 30,
      };

      final api = FakeStatesApiClient(activities: [template]);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-07', now: now), app, disableAnimations: true));
      await tester.pumpAndSettle();

      // Tap 10:00 hour line
      await tester.tap(find.text('10:00'));
      await tester.pumpAndSettle();

      // Quick add sheet does not open
      expect(find.text('Add at 10:00'), findsNothing);
    });

    testWidgets('past day: activity details sheet hides Move/Remove but allows Validate for caregiver',
        (tester) async {
      setPhoneSize(tester);
      final act = {
        'id': 301,
        'title': 'Morning Medicine',
        'type': 'care',
        'category': 'care',
        'status': 'pending_validation',
        'starts_at': '2026-10-07T09:00:00Z',
        'duration_minutes': 30,
        'assigned_to': 2,
        'assigned_alias': 'Alex',
        'coin_value': 15,
        'is_recurrent': true,
      };

      final api = FakeStatesApiClient(activities: [act]);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-07', now: now), app, disableAnimations: true));
      await tester.pumpAndSettle();

      // Tap the block title to open activity details sheet
      await tester.tap(find.descendant(
        of: find.byType(DayActivityBlock),
        matching: find.textContaining('Morning Medicine', findRichText: true),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Actions Move, Remove, Repeat are NOT present
      expect(find.text('Move'), findsNothing);
      expect(find.text('Remove'), findsNothing);
      expect(find.text('Repeat'), findsNothing);

      // Validate IS present because caregiver validating someone else
      expect(find.text('Validate'), findsOneWidget);

      await tester.tap(find.text('Validate'));
      await tester.pumpAndSettle();

      expect(api.postCalls.any((c) => c.contains('/validate')), isTrue);
      // Elapse AppState.setSuccess 3.5s auto-clear timer
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('P2-10: 4. Error / offline states', () {
    testWidgets('load failure with no data shows inline LoadErrorState with Retry in grid area',
        (tester) async {
      setPhoneSize(tester);
      final api = FakeStatesApiClient()..shouldFailGetActivities = true;
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(DailyScreen(now: now), app, disableAnimations: true));
      await tester.pumpAndSettle();

      // WeekStrip is still present at top (not full-screen error)
      expect(find.byType(WeekStrip), findsOneWidget);

      // LoadErrorState is present inside grid area
      expect(find.byType(LoadErrorState), findsOneWidget);
      expect(find.text("Couldn't load data.\nCheck your connection and try again."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Tapping retry reloads
      api.shouldFailGetActivities = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.byType(LoadErrorState), findsNothing);
    });

    testWidgets('refresh failure with existing data keeps grid and shows SnackBar',
        (tester) async {
      setPhoneSize(tester);
      final act = {
        'id': 101,
        'title': 'Existing Task',
        'type': 'care',
        'category': 'care',
        'status': 'approved',
        'starts_at': '2026-10-08T10:00:00Z',
        'duration_minutes': 60,
        'assigned_to': 1,
      };

      final api = FakeStatesApiClient(activities: [act]);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(DailyScreen(now: now, active: true), app, disableAnimations: true));
      await tester.pumpAndSettle();

      expect(find.text('Existing Task'), findsOneWidget);

      // Set API to fail on next call
      api.shouldFailGetActivities = true;

      // Trigger refresh
      await tester.pumpWidget(_wrap(DailyScreen(now: now, active: false), app, disableAnimations: true));
      await tester.pump();
      await tester.pumpWidget(_wrap(DailyScreen(now: now, active: true), app, disableAnimations: true));
      await tester.pumpAndSettle();

      // Task is still visible!
      expect(find.text('Existing Task'), findsOneWidget);

      // SnackBar with error message is displayed
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text("Couldn't load data.\nCheck your connection and try again."),
        ),
        findsOneWidget,
      );
    });
  });

  group('P2-10: 5. Guided tour targets', () {
    testWidgets('tour targets exist on narrow layout',
        (tester) async {
      setPhoneSize(tester);
      SharedPreferences.setMockInitialValues({
        'tour.seen.welcome': true,
        'tour.seen.daily': false, // Tour allowed
      });

      final api = FakeStatesApiClient(activities: []);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(DailyScreen(now: now), app, disableAnimations: true));
      await tester.pumpAndSettle();

      // Tour coach marks appear:
      // First coach mark targets tray handle: "Drag a task onto the day"
      expect(find.text('Drag a task onto the day'), findsOneWidget);
      expect(find.text('Drag a task onto the day to schedule it at that time.'), findsOneWidget);

      // Advance tour
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // Second coach mark targets empty hour: "Tap an hour"
      expect(find.text('Tap an hour'), findsOneWidget);
      expect(find.text('Or tap an hour to add something there.'), findsOneWidget);

      // Finish tour
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      expect(find.text('Tap an hour'), findsNothing);
    });
  });

  group('P2-10: 6. Semantics hints', () {
    testWidgets('tray chips, blocks, and hour lines expose accessibility semantics',
        (tester) async {
      setPhoneSize(tester);
      final template = {
        'id': 201,
        'title': 'Dishwashing',
        'type': 'household',
        'category': 'care',
        'is_template': true,
        'status': 'approved',
        'coin_value': 10,
        'duration_minutes': 30,
      };

      final scheduled = {
        'id': 101,
        'title': 'Walk Dog',
        'type': 'care',
        'category': 'care',
        'status': 'approved',
        'starts_at': '2026-10-08T15:00:00Z',
        'duration_minutes': 45,
        'assigned_to': 1,
        'coin_value': 15,
      };

      final api = FakeStatesApiClient(activities: [template, scheduled]);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(_wrap(DailyScreen(now: now), app, disableAnimations: true));
      await tester.pumpAndSettle();

      // 1. Tray chip semantics hint
      final chipSemantics = tester.getSemantics(find.bySemanticsLabel(RegExp('Dishwashing')));
      expect(chipSemantics.hint, contains('Double-tap to choose a time'));

      // 2. Scheduled activity block semantics hint
      final blockSemantics = tester.getSemantics(find.bySemanticsLabel(RegExp('Walk Dog')));
      expect(blockSemantics.hint, contains('Double-tap for actions'));

      // 3. Grid hour lines expose button for screen readers
      final hourSemantics = tester.getSemantics(find.bySemanticsLabel('Add at 15:00'));
      expect(hourSemantics.flagsCollection.isButton, isTrue);

      semantics.dispose();
    });
  });
}
