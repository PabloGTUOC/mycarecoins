import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/daily_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';

class FakeActivitySheetApiClient extends ApiClient {
  List<Map<String, dynamic>> activities;
  List<Map<String, dynamic>> absences;
  List<Map<String, dynamic>> requests;
  List<Map<String, dynamic>> members;

  final List<String> getCalls = [];
  final List<String> postCalls = [];
  final List<String> patchCalls = [];
  final List<String> deleteCalls = [];
  final List<Map<String, dynamic>> postBodies = [];
  final List<Map<String, dynamic>> patchBodies = [];

  FakeActivitySheetApiClient({
    this.activities = const [],
    this.absences = const [],
    this.requests = const [],
    this.members = const [],
  });

  @override
  Future<dynamic> get(String path) async {
    getCalls.add(path);
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
      // POST /schedule answers { activity: {...}, warning: ... }
      final templateId = int.tryParse(path.split('/')[3]) ?? 999;
      final template = activities.firstWhere(
        (a) => a['id'] == templateId,
        orElse: () => {'id': templateId, 'title': 'Scheduled Task'},
      );
      final startsAt = (body is Map ? body['startsAt'] : null)?.toString();
      final newAct = {
        'id': 999,
        'title': template['title'] ?? 'Scheduled Task',
        'type': template['type'] ?? 'care',
        'category': template['category'] ?? 'care',
        'status': 'approved',
        'assigned_to': 1,
        'starts_at': startsAt,
        'duration_minutes': template['duration_minutes'] ?? 30,
        'coin_value': template['coin_value'] ?? 0,
      };
      activities = [...activities, newAct];
      return {
        'activity': newAct,
        'warning': null,
      };
    }
    if (path.contains('/bounty')) {
      return {'data': {'success': true}};
    }
    if (path.contains('/accept-bounty')) {
      return {'data': {'success': true}};
    }
    return {'success': true};
  }

  @override
  Future<dynamic> patch(String path, [Object? body]) async {
    patchCalls.add(path);
    if (body is Map<String, dynamic>) {
      patchBodies.add(body);
    }
    if (path.endsWith('/time')) {
      // PATCH /time answers { activity: {...} }
      final parts = path.split('/');
      final actId = int.tryParse(parts[3]) ?? 0;
      final startsAt = (body is Map ? body['startsAt'] : null)?.toString();
      final idx = activities.indexWhere((a) => a['id'] == actId);
      if (idx >= 0) {
        final updated = Map<String, dynamic>.from(activities[idx]);
        updated['starts_at'] = startsAt;
        activities[idx] = updated;
        return {'activity': updated};
      }
      return {
        'activity': {
          'id': actId,
          'starts_at': startsAt,
        }
      };
    }
    return {'success': true};
  }

  @override
  Future<dynamic> delete(String path, [Object? body]) async {
    deleteCalls.add(path);
    // DELETE answers { success: true }
    return {'success': true};
  }
}

Widget _wrap(Widget child, AppState app) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ScaffoldMessenger(
          child: child is DailyScreen ? child : Center(child: child)),
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

  group('P2-9: Today quick add and activity sheet', () {
    testWidgets(
        '1. Empty-slot tap opens Add at HH:MM snapped DOWN to 15m and schedules on one tap',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeActivitySheetApiClient(
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

      // Now is 08:00 on 2026-10-06
      final now = DateTime.parse('2026-10-06T08:00:00Z');
      await tester
          .pumpWidget(_wrap(DailyScreen(date: '2026-10-06', now: now), app));
      await tester.pumpAndSettle();

      // No ListView should be in the screen
      expect(find.byType(ListView), findsNothing);

      // Past time: tap at 07:00 when now is 08:00 does nothing
      final hour7 = find.text('07:00');
      expect(hour7, findsOneWidget);
      final center7 = tester.getCenter(hour7);
      await tester.tapAt(Offset(center7.dx + 150, center7.dy + 10));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.textContaining('Add at'), findsNothing);

      // Future time: tap at 10:00 + 20dp (~10:18), snapped DOWN to 10:15
      final hour10 = find.text('10:00');
      expect(hour10, findsOneWidget);
      final center10 = tester.getCenter(hour10);

      await tester.tapAt(Offset(center10.dx + 150, center10.dy));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Quick add sheet opened with title "Add at 10:15"
      expect(find.text('Add at 10:15'), findsOneWidget);
      expect(find.text('Time for me'), findsOneWidget);
      final sheetBath = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Bath'),
      );
      expect(sheetBath, findsOneWidget);

      // Sheet uses SingleChildScrollView, NO ListView
      expect(find.byType(ListView), findsNothing);

      // Tap Bath in the sheet -> schedules immediately without further dialog
      await tester.tap(sheetBath);
      await tester.pumpAndSettle();

      // Sheet closed, scheduled via POST /schedule
      expect(api.postCalls.any((c) => c == '/api/activities/30/schedule'),
          isTrue);
      expect(api.postBodies.isNotEmpty, isTrue);
      final postedStartsAt =
          DateTime.parse(api.postBodies.last['startsAt'] as String).toLocal();
      expect(postedStartsAt.hour, equals(10));
      expect(postedStartsAt.minute, equals(15));

      // SnackBar shows Bath at 10:15 and Undo
      expect(find.text('Bath at 10:15'), findsOneWidget);
      final undoBtn = find.text('Undo');
      expect(undoBtn, findsOneWidget);

      // Tapping Undo removes the scheduled instance
      await tester.tap(undoBtn);
      await tester.pumpAndSettle();
      expect(api.deleteCalls.any((c) => c == '/api/activities/999'), isTrue);
    });

    testWidgets('2. Block tap shows the right actions for all 6 scenarios',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final activities = [
        // 1. My ordinary task
        {
          'id': 101,
          'title': 'My Cook Task',
          'is_recurrent': true,
          'type': 'household',
          'category': 'care',
          'status': 'approved',
          'assigned_to': 1,
          'coin_value': 5,
          'bounty_amount': 0,
          'starts_at': '2026-10-06T09:00:00Z',
          'duration_minutes': 60,
        },
        // 2. Someone else task with a bounty
        {
          'id': 102,
          'title': 'Other Bounty Task',
          'type': 'household',
          'category': 'care',
          'status': 'approved',
          'assigned_to': 2,
          'assigned_alias': 'Alex',
          'coin_value': 5,
          'bounty_amount': 15,
          'starts_at': '2026-10-06T11:00:00Z',
          'duration_minutes': 60,
        },
        // 3. Pending validation for caregiver
        {
          'id': 103,
          'title': 'Pending Validate Task',
          'type': 'care',
          'category': 'care',
          'status': 'pending_validation',
          'assigned_to': 2,
          'assigned_alias': 'Alex',
          'coin_value': 5,
          'bounty_amount': 0,
          'starts_at': '2026-10-06T13:00:00Z',
          'duration_minutes': 60,
        },
        // 4. Coverage
        {
          'id': 104,
          'title': 'Coverage Shift',
          'type': 'coverage',
          'category': 'care',
          'status': 'approved',
          'assigned_to': 1,
          'starts_at': '2026-10-06T15:00:00Z',
          'duration_minutes': 60,
        },
        // 5. My covered personal time
        {
          'id': 105,
          'title': 'My Covered Rest',
          'type': 'rest',
          'category': 'self',
          'status': 'approved',
          'assigned_to': 1,
          'counterpart_activity_id': 104,
          'starts_at': '2026-10-06T15:00:00Z',
          'duration_minutes': 60,
        },
        // 6. Someone else personal time
        {
          'id': 106,
          'title': 'Alex Free Time',
          'type': 'rest',
          'category': 'self',
          'status': 'approved',
          'assigned_to': 2,
          'assigned_alias': 'Alex',
          'starts_at': '2026-10-06T17:00:00Z',
          'duration_minutes': 60,
        },
      ];

      final api = FakeActivitySheetApiClient(activities: activities);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      final now = DateTime.parse('2026-10-06T08:00:00Z');
      await tester
          .pumpWidget(_wrap(DailyScreen(date: '2026-10-06', now: now), app));
      await tester.pumpAndSettle();

      // --- Scenario 1: My ordinary task (recurring, so the title has a 🔁 span) ---
      await tester.tap(find.textContaining('My Cook Task', findRichText: true).first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Delegate'), findsOneWidget);
      expect(find.text('Repeat'), findsOneWidget);
      expect(find.text('Move'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      expect(find.text('Validate'), findsNothing);
      expect(find.textContaining('Take over'), findsNothing);

      // Dismiss sheet
      Navigator.pop(tester.element(find.text('Delegate')));
      await tester.pumpAndSettle();

      // --- Scenario 2: Someone else task with a bounty ---
      await tester.tap(find.text('Other Bounty Task'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Take over (+15 cc)'), findsOneWidget);
      expect(find.text('Delegate'), findsNothing);
      expect(find.text('Repeat'), findsNothing);
      // A caregiver may move or remove someone else's task (server rule).
      expect(find.text('Move'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      expect(find.text('Validate'), findsNothing);

      // Dismiss sheet
      Navigator.pop(tester.element(find.text('Take over (+15 cc)')));
      await tester.pumpAndSettle();

      // --- Scenario 3: Pending validation for caregiver ---
      await tester.tap(find.text('Pending Validate Task'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Validate'), findsOneWidget);
      expect(find.text('Delegate'), findsNothing);
      expect(find.text('Repeat'), findsNothing);
      // Only upcoming (approved) activities move; the server still lets a
      // caregiver remove one waiting for validation.
      expect(find.text('Move'), findsNothing);
      expect(find.text('Remove'), findsOneWidget);
      expect(find.textContaining('Take over'), findsNothing);

      // Dismiss sheet
      Navigator.pop(tester.element(find.text('Validate')));
      await tester.pumpAndSettle();

      // --- Scenario 4: Coverage ---
      await tester.tap(find.text('Coverage Shift'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Ends with the personal time it covers'), findsOneWidget);
      expect(find.text('Validate'), findsNothing);
      expect(find.text('Delegate'), findsNothing);
      expect(find.text('Repeat'), findsNothing);
      expect(find.text('Move'), findsNothing);
      expect(find.text('Remove'), findsNothing);
      expect(find.textContaining('Take over'), findsNothing);

      // Dismiss sheet
      Navigator.pop(
          tester.element(find.text('Ends with the personal time it covers')));
      await tester.pumpAndSettle();

      // --- Scenario 5: My covered personal time ---
      await tester.tap(find.text('My Covered Rest'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Remove'), findsOneWidget);
      expect(find.text('Move'), findsNothing);
      expect(find.text('Delegate'), findsNothing);
      expect(find.text('Repeat'), findsNothing);
      expect(find.text('Validate'), findsNothing);
      expect(find.textContaining('Take over'), findsNothing);

      // Dismiss sheet
      Navigator.pop(tester.element(find.text('Remove')));
      await tester.pumpAndSettle();

      // --- Scenario 6: Someone else personal time ---
      await tester.tap(find.text('Alex Free Time'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // View only: no action buttons
      expect(find.text('Remove'), findsNothing);
      expect(find.text('Move'), findsNothing);
      expect(find.text('Delegate'), findsNothing);
      expect(find.text('Repeat'), findsNothing);
      expect(find.text('Validate'), findsNothing);
      expect(find.textContaining('Take over'), findsNothing);
    });

    testWidgets(
        '3. Move button opens showTimePicker and calls PATCH /time; Undo restores old start',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeActivitySheetApiClient(
        activities: [
          {
            'id': 101,
            'title': 'My Move Task',
            'type': 'household',
            'category': 'care',
            'status': 'approved',
            'assigned_to': 1,
            'starts_at': '2026-10-06T10:00:00Z',
            'duration_minutes': 60,
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      final now = DateTime.parse('2026-10-06T08:00:00Z');
      await tester
          .pumpWidget(_wrap(DailyScreen(date: '2026-10-06', now: now), app));
      await tester.pumpAndSettle();

      // Tap block
      await tester.tap(find.text('My Move Task'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Tap Move button
      final moveBtn = find.text('Move');
      expect(moveBtn, findsOneWidget);
      await tester.tap(moveBtn);
      await tester.pumpAndSettle();

      // TimePickerDialog opens
      expect(find.byType(TimePickerDialog), findsOneWidget);

      // Tap OK
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // PATCH /time called
      expect(api.patchCalls.any((c) => c == '/api/activities/101/time'), isTrue);

      // SnackBar shows Undo
      final undoBtn = find.text('Undo');
      expect(undoBtn, findsOneWidget);

      // Tap Undo -> restores old start
      await tester.tap(undoBtn);
      await tester.pumpAndSettle();

      expect(api.patchCalls.where((c) => c == '/api/activities/101/time').length,
          equals(2));
      final restoredStartsAt =
          api.patchBodies.last['startsAt'] as String;
      expect(DateTime.parse(restoredStartsAt).toUtc().hour, equals(10));
    });

    testWidgets(
        '4. Drag-to-move calls PATCH /time with snapped time and Undo restores',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeActivitySheetApiClient(
        activities: [
          {
            'id': 101,
            'title': 'Drag Move Task',
            'type': 'care',
            'category': 'care',
            'status': 'approved',
            'assigned_to': 1,
            'starts_at': '2026-10-06T10:00:00Z',
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
      await tester
          .pumpWidget(_wrap(DailyScreen(date: '2026-10-06', now: now), app));
      await tester.pumpAndSettle();

      final block = find.text('Drag Move Task');
      expect(block, findsOneWidget);

      // Long-press to drag
      final gesture = await tester.startGesture(tester.getCenter(block));
      await tester.pump(const Duration(milliseconds: 600));

      // Move to 12:00
      final gridCenter = tester.getCenter(find.text('12:00'));
      await gesture.moveTo(Offset(gridCenter.dx + 100, gridCenter.dy));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // PATCH /time called
      expect(api.patchCalls.any((c) => c == '/api/activities/101/time'), isTrue);
      final movedStartsAt =
          DateTime.parse(api.patchBodies.last['startsAt'] as String).toLocal();
      expect(movedStartsAt.hour, equals(12));

      // Undo SnackBar appears
      final undoBtn = find.text('Undo');
      expect(undoBtn, findsOneWidget);

      // Tap Undo
      await tester.tap(undoBtn);
      await tester.pumpAndSettle();

      final restoredStartsAt =
          DateTime.parse(api.patchBodies.last['startsAt'] as String).toUtc();
      expect(restoredStartsAt.hour, equals(10));
    });

    testWidgets(
        '5. Remove follows rules: warning on covered personal time, series/single on recurring',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final activities = [
        {
          'id': 104,
          'title': 'Coverage Shift',
          'type': 'coverage',
          'category': 'care',
          'status': 'approved',
          'assigned_to': 2,
          'starts_at': '2026-10-06T10:00:00Z',
          'duration_minutes': 60,
        },
        {
          'id': 105,
          'title': 'My Yoga Covered',
          'type': 'rest',
          'category': 'self',
          'status': 'approved',
          'assigned_to': 1,
          'counterpart_activity_id': 104,
          'starts_at': '2026-10-06T10:00:00Z',
          'duration_minutes': 60,
        },
        {
          'id': 107,
          'title': 'Daily Morning Walk',
          'type': 'household',
          'category': 'care',
          'status': 'approved',
          'assigned_to': 1,
          'is_recurrent': true,
          'starts_at': '2026-10-06T11:30:00Z',
          'duration_minutes': 30,
        },
      ];

      final api = FakeActivitySheetApiClient(activities: activities);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.parse('2026-10-06T08:00:00Z');
      await tester
          .pumpWidget(_wrap(DailyScreen(date: '2026-10-06', now: now), app));
      await tester.pumpAndSettle();

      // --- Part A: Covered personal time remove shows counterpart warning ---
      await tester.tap(find.text('My Yoga Covered'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // Warning dialog appears
      expect(
          find.text(
              "Cancelling this also cancels the other person's coverage shift, and any sweetener comes back to you."),
          findsOneWidget);

      // Confirm remove
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(api.deleteCalls.any((c) => c == '/api/activities/105'), isTrue);

      // --- Part B: Recurring task remove shows single vs series choice ---
      await tester.tap(find.textContaining('Daily Morning Walk'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // Choice dialog appears
      expect(find.text('This one'), findsOneWidget);
      expect(find.text('Whole series'), findsOneWidget);

      // Tap 'Whole series'
      await tester.tap(find.text('Whole series'));
      await tester.pumpAndSettle();

      expect(
          api.deleteCalls
              .any((c) => c == '/api/activities/107?series=true'),
          isTrue);

      // Drain success toast timer from runAction
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('6. Quick add Care filter keeps household tasks out',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Care work is category 'care'; the type tells care from household.
      final api = FakeActivitySheetApiClient(
        activities: [
          {
            'id': 30,
            'title': 'Bath',
            'category': 'care',
            'type': 'care',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 30,
            'coin_value': 3,
          },
          {
            'id': 31,
            'title': 'Laundry',
            'category': 'care',
            'type': 'household',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 30,
            'coin_value': 2,
          },
        ],
      );
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      final now = DateTime.parse('2026-10-06T08:00:00Z');
      await tester
          .pumpWidget(_wrap(DailyScreen(date: '2026-10-06', now: now), app));
      await tester.pumpAndSettle();

      final center10 = tester.getCenter(find.text('10:00'));
      await tester.tapAt(Offset(center10.dx + 150, center10.dy));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      Finder inSheet(String text) => find.descendant(
          of: find.byType(BottomSheet), matching: find.text(text));
      expect(inSheet('Bath'), findsOneWidget);
      expect(inSheet('Laundry'), findsOneWidget);

      await tester.tap(find.descendant(
          of: find.byType(BottomSheet), matching: find.text('Care')));
      await tester.pumpAndSettle();
      expect(inSheet('Bath'), findsOneWidget);
      expect(inSheet('Laundry'), findsNothing);

      await tester.tap(find.descendant(
          of: find.byType(BottomSheet), matching: find.text('Household')));
      await tester.pumpAndSettle();
      expect(inSheet('Bath'), findsNothing);
      expect(inSheet('Laundry'), findsOneWidget);
    });

    testWidgets(
        "7. A member who is not a caregiver cannot move or remove someone else's task",
        (tester) async {
      tester.view.physicalSize = const Size(500, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeActivitySheetApiClient(activities: [
        {
          'id': 201,
          'title': 'Their Task',
          'category': 'care',
          'type': 'household',
          'status': 'approved',
          'assigned_to': 2,
          'assigned_alias': 'Alex',
          'coin_value': 5,
          'bounty_amount': 0,
          'starts_at': '2026-10-06T11:00:00Z',
          'duration_minutes': 60,
        },
      ]);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'member'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      final now = DateTime.parse('2026-10-06T08:00:00Z');
      await tester
          .pumpWidget(_wrap(DailyScreen(date: '2026-10-06', now: now), app));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Their Task'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Their Task'), findsWidgets);
      expect(find.text('Move'), findsNothing);
      expect(find.text('Remove'), findsNothing);
    });
  });
}
