import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/daily_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';

class FakeTrayApiClient extends ApiClient {
  List<Map<String, dynamic>> activities;
  List<Map<String, dynamic>> absences;
  List<Map<String, dynamic>> requests;
  List<Map<String, dynamic>> members;

  final List<String> postCalls = [];
  final List<String> deleteCalls = [];
  final List<Map<String, dynamic>> postBodies = [];

  FakeTrayApiClient({
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
    postCalls.add(path);
    if (body is Map<String, dynamic>) {
      postBodies.add(body);
    }
    if (path.contains('/schedule')) {
      // The real shape of POST /api/activities/:id/schedule.
      return {
        'activity': {
          'id': 999,
          'title': 'Scheduled Task',
          'starts_at': (body is Map ? body['startsAt'] : null),
        },
        'warning': null,
      };
    }
    return {'success': true};
  }

  @override
  Future<dynamic> delete(String path, [Object? body]) async {
    deleteCalls.add(path);
    return {'success': true};
  }
}

Widget _wrap(Widget child, AppState app) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ScaffoldMessenger(child: child is DailyScreen ? child : Center(child: child)),
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

  group('P2-8: Task Tray and Drag-to-Schedule', () {
    testWidgets('1. Tray renders collapsed with chips ordered by frequency',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeTrayApiClient(
        activities: [
          // Templates
          {
            'id': 10,
            'title': 'Laundry',
            'type': 'household',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 45,
            'coin_value': 2,
          },
          {
            'id': 20,
            'title': 'Cooking',
            'type': 'household',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 60,
            'coin_value': 5,
          },
          {
            'id': 30,
            'title': 'Bath',
            'type': 'care',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 30,
            'coin_value': 3,
          },
          // Non-template instances for frequency counting
          // Cooking: 3 instances
          {'id': 101, 'title': 'Cooking', 'is_template': false, 'status': 'completed'},
          {'id': 102, 'title': 'Cooking', 'is_template': false, 'status': 'completed'},
          {'id': 103, 'title': 'Cooking', 'is_template': false, 'status': 'completed'},
          // Bath: 1 instance
          {'id': 104, 'title': 'Bath', 'is_template': false, 'status': 'completed'},
          // Laundry: 0 instances
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      final now = DateTime.parse('2026-10-06T08:00:00Z');
      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-06', now: now), app));
      await tester.pumpAndSettle();

      // Header label visible
      expect(find.text('Tasks · drag onto the day'), findsOneWidget);

      // Chips rendered in order of frequency: Cooking (3) > Bath (1) > Laundry (0)
      final cookingFinder = find.text('Cooking');
      final bathFinder = find.text('Bath');
      final laundryFinder = find.text('Laundry');

      expect(cookingFinder, findsOneWidget);
      expect(bathFinder, findsOneWidget);
      expect(laundryFinder, findsOneWidget);

      final cookingDx = tester.getTopLeft(cookingFinder).dx;
      final bathDx = tester.getTopLeft(bathFinder).dx;
      final laundryDx = tester.getTopLeft(laundryFinder).dx;

      expect(cookingDx, lessThan(bathDx));
      expect(bathDx, lessThan(laundryDx));
    });

    testWidgets('2. Expanding tray shows search and Time for me first',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeTrayApiClient(
        activities: [
          {
            'id': 20,
            'title': 'Cooking',
            'type': 'household',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 60,
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      final now = DateTime.parse('2026-10-06T08:00:00Z');
      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-06', now: now), app));
      await tester.pumpAndSettle();

      // "All tasks" in the tray header expands it (phones have no FAB).
      final allTasks = find.text('All tasks');
      expect(allTasks, findsOneWidget);
      await tester.tap(allTasks);
      await tester.pumpAndSettle();

      // Search field is present
      expect(find.byType(TextField), findsOneWidget);

      // "Time for me" is visible as first row
      final timeForMeFinder = find.text('Time for me');
      expect(timeForMeFinder, findsOneWidget);

      final cookingFinder = find.text('Cooking');
      expect(cookingFinder, findsOneWidget);

      // "Time for me" appears above the tasks
      expect(tester.getTopLeft(timeForMeFinder).dy,
          lessThan(tester.getTopLeft(cookingFinder).dy));
    });

    testWidgets('3. Drop onto grid schedules at 15-minute snapped time without dialog, shows Undo',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeTrayApiClient(
        activities: [
          {
            'id': 30,
            'title': 'Bath',
            'type': 'care',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 30,
            'coin_value': 3,
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      // Now is 08:00
      final now = DateTime.parse('2026-10-06T08:00:00Z');
      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-06', now: now), app));
      await tester.pumpAndSettle();

      final chip = find.text('Bath');
      expect(chip, findsOneWidget);

      // Start long-press drag
      final gesture = await tester.startGesture(tester.getCenter(chip));
      await tester.pump(const Duration(milliseconds: 600)); // satisfy LongPressDraggable timeout

      // Move onto grid over 10:15
      // Grid starts at 06:00. 10:15 is (10.25 - 6) = 4.25 hours from top.
      // With kGridHeight = 1152, 1 hour = 64 dp. 4.25 * 64 = 272 dp.
      // Find the grid container position:
      final gridCenter = tester.getCenter(find.text('10:00'));
      await gesture.moveTo(Offset(gridCenter.dx + 100, gridCenter.dy + 16)); // 16dp down = +15 minutes
      await tester.pump();

      // Check ghost block appears with 15-minute snapped time range
      expect(find.text('10:15 to 10:45'), findsOneWidget);

      // Release drop
      await gesture.up();
      await tester.pumpAndSettle();

      // No time picker dialog appeared
      expect(find.byType(TimePickerDialog), findsNothing);

      // Immediate schedule POST was called with 10:15 startsAt
      expect(api.postCalls.any((c) => c == '/api/activities/30/schedule'), isTrue);
      expect(api.postBodies.isNotEmpty, isTrue);
      final startsAtStr = api.postBodies.first['startsAt'].toString();
      final scheduledDt = DateTime.parse(startsAtStr).toLocal();
      expect(scheduledDt.hour, 10);
      expect(scheduledDt.minute, 15);

      // SnackBar shows "Bath at 10:15" with Undo action
      expect(find.text('Bath at 10:15'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('4. Undo issues delete for the scheduled instance',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeTrayApiClient(
        activities: [
          {
            'id': 30,
            'title': 'Bath',
            'type': 'care',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 30,
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      final now = DateTime.parse('2026-10-06T08:00:00Z');
      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-06', now: now), app));
      await tester.pumpAndSettle();

      // Long press drag and drop
      final gesture = await tester.startGesture(tester.getCenter(find.text('Bath')));
      await tester.pump(const Duration(milliseconds: 600));

      final gridCenter = tester.getCenter(find.text('10:00'));
      await gesture.moveTo(Offset(gridCenter.dx + 100, gridCenter.dy + 16));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Tap Undo in SnackBar
      final undoBtn = find.text('Undo');
      expect(undoBtn, findsOneWidget);
      await tester.tap(undoBtn);
      await tester.pumpAndSettle();

      // Verify DELETE /api/activities/999 was called
      expect(api.deleteCalls.any((c) => c == '/api/activities/999'), isTrue);
    });

    testWidgets('5. Drop over past time, absence, or overlapping activity is refused',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeTrayApiClient(
        activities: [
          {
            'id': 30,
            'title': 'Bath',
            'type': 'care',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 30,
          },
          // Existing non-coverage activity overlapping 16:00-17:00
          {
            'id': 201,
            'title': 'Dinner prep',
            'type': 'household',
            'is_template': false,
            'status': 'approved',
            'starts_at': '2026-10-06T16:00:00',
            'duration_minutes': 60,
            'assigned_to': 1,
          },
        ],
        // Absence overlapping 13:00-14:30
        absences: [
          {
            'id': 501,
            'user_id': 1,
            'title': 'Doctor appointment',
            'start_time': '2026-10-06T13:00:00',
            'end_time': '2026-10-06T14:30:00',
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      // Now is 11:00
      final now = DateTime(2026, 10, 6, 11, 0);
      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-06', now: now), app));
      await tester.pumpAndSettle();

      // Case A: Drag over past time (08:00)
      var gesture = await tester.startGesture(tester.getCenter(find.text('Bath')));
      await tester.pump(const Duration(milliseconds: 600));

      final center08 = tester.getCenter(find.text('08:00'));
      await gesture.moveTo(Offset(center08.dx + 100, center08.dy));
      await tester.pump();

      expect(find.text('Time has passed'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(api.postCalls.isEmpty, isTrue); // Refused!

      // Case B: Drag over absence (13:30)
      gesture = await tester.startGesture(tester.getCenter(find.text('Bath')));
      await tester.pump(const Duration(milliseconds: 600));

      final center13 = tester.getCenter(find.text('13:00'));
      await gesture.moveTo(Offset(center13.dx + 100, center13.dy + 32)); // ~13:30
      await tester.pump();

      expect(find.text('You are away'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(api.postCalls.isEmpty, isTrue); // Refused!

      // Case C: Drag over overlapping activity (16:15)
      gesture = await tester.startGesture(tester.getCenter(find.text('Bath')));
      await tester.pump(const Duration(milliseconds: 600));

      final center16 = tester.getCenter(find.text('16:00'));
      await gesture.moveTo(Offset(center16.dx + 100, center16.dy + 16)); // ~16:15
      await tester.pump();

      expect(find.text('Already scheduled'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(api.postCalls.isEmpty, isTrue); // Refused!
    });

    testWidgets('6. Tapping a chip opens showTimePicker with sensible initial time',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeTrayApiClient(
        activities: [
          {
            'id': 30,
            'title': 'Bath',
            'type': 'care',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 30,
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      // Now is 10:05 today -> sensible time is 10:15
      final now = DateTime(2026, 10, 6, 10, 5);
      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-06', now: now), app));
      await tester.pumpAndSettle();

      // Tap 'Bath' chip in tray
      await tester.tap(find.text('Bath'));
      await tester.pumpAndSettle();

      // TimePickerDialog opens
      expect(find.byType(TimePickerDialog), findsOneWidget);

      // Confirm picker
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Scheduled at picked time
      expect(api.postCalls.any((c) => c == '/api/activities/30/schedule'), isTrue);
      expect(find.text('Bath at 10:15'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('7. Past day chips are not draggable and tapping shows "This day has passed"',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeTrayApiClient(
        activities: [
          {
            'id': 30,
            'title': 'Bath',
            'type': 'care',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 30,
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      // Viewing yesterday: 2026-10-05 while now is 2026-10-06
      final now = DateTime(2026, 10, 6, 10, 0);
      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-05', now: now), app));
      await tester.pumpAndSettle();

      // Tray is visible
      expect(find.text('Tasks · drag onto the day'), findsOneWidget);

      // Chip 'Bath' is rendered
      final chip = find.text('Bath');
      expect(chip, findsOneWidget);

      // Chip is NOT a LongPressDraggable
      expect(find.byType(LongPressDraggable), findsNothing);

      // Tapping the chip shows SnackBar "This day has passed"
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(
          find.descendant(
              of: find.byType(SnackBar),
              matching: find.text('This day has passed')),
          findsOneWidget);
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(api.postCalls.isEmpty, isTrue);
    });
  });
}
