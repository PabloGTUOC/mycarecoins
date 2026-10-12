import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/daily_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/theme/app_theme.dart';

class FakeDailyRemoveApiClient extends ApiClient {
  List<Map<String, dynamic>> activities;
  List<Map<String, dynamic>> absences;
  List<Map<String, dynamic>> requests;
  List<Map<String, dynamic>> members;

  final List<String> getCalls = [];
  final List<String> postCalls = [];
  final List<String> patchCalls = [];
  final List<String> deleteCalls = [];

  bool shouldFailDelete = false;

  FakeDailyRemoveApiClient({
    this.activities = const [],
    this.absences = const [],
    this.requests = const [],
    this.members = const [],
  });

  @override
  Future<dynamic> get(String path) async {
    getCalls.add(path);
    if (path.startsWith('/api/activities')) {
      return {'activities': List<Map<String, dynamic>>.from(activities)};
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
    if (shouldFailDelete) {
      throw ApiException(ApiErrorKind.server, serverMessage: 'Delete failed');
    }
    final rawId = path.split('?').first.split('/').last;
    activities.removeWhere((a) => '${a['id']}' == rawId);
    return {'success': true};
  }
}

class _ToastListener extends StatefulWidget {
  final Widget child;
  const _ToastListener({required this.child});

  @override
  State<_ToastListener> createState() => _ToastListenerState();
}

class _ToastListenerState extends State<_ToastListener> {
  String _lastToast = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    app.l10n = AppLocalizations.of(context);
    final msg = app.error.isNotEmpty ? app.error : app.success;
    if (msg.isEmpty) {
      _lastToast = '';
    } else if (msg != _lastToast) {
      _lastToast = msg;
      final isError = app.error.isNotEmpty;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(msg),
            backgroundColor: isError ? AppColors.danger : AppColors.success,
            duration: Duration(milliseconds: isError ? 5000 : 3500),
          ));
      });
    }
    return widget.child;
  }
}

Widget _wrap(Widget child, AppState app) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, materialAppChild) {
        return _ToastListener(
          child: materialAppChild!,
        );
      },
      home: child is DailyScreen ? child : Center(child: child),
    ),
  );
}

void main() {
  final now = DateTime.parse('2026-10-12T10:00:00Z');

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tour.seen.welcome': true,
      'tour.seen.daily': true,
      'tour.seen.dashboard': true,
      'tour.seen.checklist-dismissed': true,
    });
  });

  group('P6-2: Undo for removing a task', () {
    testWidgets(
        'one-off care task: remove hides immediately, shows Undo toast without DELETE; tap Undo restores it; timeout sends DELETE',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeDailyRemoveApiClient(
        activities: [
          {
            'id': 101,
            'title': 'Morning Care',
            'type': 'care',
            'category': 'care',
            'status': 'approved',
            'assigned_to': 1,
            'starts_at': '2026-10-12T09:00:00Z',
            'duration_minutes': 60,
            'coin_value': 10,
            'is_recurrent': false,
          },
        ],
        members: [
          {'id': 1, 'display_name': 'Me', 'role': 'caregiver', 'status': 'active'},
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-12', now: now), app));
      await tester.pumpAndSettle();

      // Task is visible on today's grid
      expect(find.text('Morning Care'), findsOneWidget);

      // Tap the task to open bottom sheet
      await tester.tap(find.text('Morning Care'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Tap Remove button
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // It disappears at once
      expect(find.text('Morning Care'), findsNothing);

      // SnackBar shows "Removed "Morning Care"." with Undo
      expect(find.text('Removed "Morning Care".'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      // And NO DELETE has been sent yet
      expect(api.deleteCalls, isEmpty);

      // Tap Undo
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      // Task is back
      expect(find.text('Morning Care'), findsOneWidget);

      // Wait past the snackbar duration: no DELETE is sent
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(api.deleteCalls, isEmpty);

      // Remove again, let the snackbar time out -> exactly one DELETE /api/activities/<id>
      await tester.tap(find.text('Morning Care'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Morning Care'), findsNothing);
      expect(find.text('Removed "Morning Care".'), findsOneWidget);

      // Let the snackbar time out (5s duration + 1s buffer)
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      // Exactly one DELETE was sent
      expect(api.deleteCalls, equals(['/api/activities/101']));
      expect(find.text('Morning Care'), findsNothing);

      app.dispose();
    });

    testWidgets('one-off care task: failed DELETE causes task to reappear and shows error toast',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeDailyRemoveApiClient(
        activities: [
          {
            'id': 101,
            'title': 'Morning Care',
            'type': 'care',
            'category': 'care',
            'status': 'approved',
            'assigned_to': 1,
            'starts_at': '2026-10-12T09:00:00Z',
            'duration_minutes': 60,
            'coin_value': 10,
            'is_recurrent': false,
          },
        ],
        members: [
          {'id': 1, 'display_name': 'Me', 'role': 'caregiver', 'status': 'active'},
        ],
      );
      api.shouldFailDelete = true;

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-12', now: now), app));
      await tester.pumpAndSettle();

      expect(find.text('Morning Care'), findsOneWidget);

      // Open sheet and remove
      await tester.tap(find.text('Morning Care'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // Disappears initially
      expect(find.text('Morning Care'), findsNothing);
      expect(find.text('Removed "Morning Care".'), findsOneWidget);
      expect(api.deleteCalls, isEmpty);

      // Let the snackbar time out to trigger DELETE
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      // DELETE was called and failed
      expect(api.deleteCalls, equals(['/api/activities/101']));

      // Task reappears because DELETE failed
      expect(find.text('Morning Care'), findsOneWidget);

      // Error toast shows
      expect(app.error, 'Delete failed');
      expect(find.text('Delete failed'), findsOneWidget);

      app.dispose();
    });

    testWidgets('recurring task: "This one" uses undo snackbar',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeDailyRemoveApiClient(
        activities: [
          {
            'id': 202,
            'title': 'Daily Walk',
            'type': 'care',
            'category': 'care',
            'status': 'approved',
            'assigned_to': 1,
            'starts_at': '2026-10-12T11:00:00Z',
            'duration_minutes': 30,
            'coin_value': 5,
            'is_recurrent': true,
          },
        ],
        members: [
          {'id': 1, 'display_name': 'Me', 'role': 'caregiver', 'status': 'active'},
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-12', now: now), app));
      await tester.pumpAndSettle();

      expect(find.textContaining('Daily Walk'), findsOneWidget);

      // Tap task and Remove
      await tester.tap(find.textContaining('Daily Walk'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // Recurring dialog appears with "This one" and "Whole series"
      expect(find.text('This one'), findsOneWidget);
      expect(find.text('Whole series'), findsOneWidget);

      // Choose "This one"
      await tester.tap(find.text('This one'));
      await tester.pumpAndSettle();

      // Disappears at once, snackbar with Undo shows, no DELETE yet
      expect(find.descendant(of: find.byType(DayActivityBlock), matching: find.textContaining('Daily Walk')), findsNothing);
      expect(find.text('Removed "Daily Walk".'), findsOneWidget);
      expect(api.deleteCalls, isEmpty);

      // Let snackbar expire
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      // Single delete sent
      expect(api.deleteCalls, equals(['/api/activities/202']));

      app.dispose();
    });

    testWidgets('recurring task: "Whole series" deletes immediately',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = FakeDailyRemoveApiClient(
        activities: [
          {
            'id': 203,
            'title': 'Evening Walk',
            'type': 'care',
            'category': 'care',
            'status': 'approved',
            'assigned_to': 1,
            'starts_at': '2026-10-12T11:00:00Z',
            'duration_minutes': 30,
            'coin_value': 5,
            'is_recurrent': true,
          },
        ],
        members: [
          {'id': 1, 'display_name': 'Me', 'role': 'caregiver', 'status': 'active'},
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-12', now: now), app));
      await tester.pumpAndSettle();

      expect(find.descendant(of: find.byType(DayActivityBlock), matching: find.textContaining('Evening Walk')), findsOneWidget);

      await tester.tap(find.textContaining('Evening Walk'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // Tap 'Whole series'
      await tester.tap(find.text('Whole series'));
      await tester.pumpAndSettle();

      // Immediate DELETE with ?series=true was sent
      expect(api.deleteCalls, contains('/api/activities/203?series=true'));
      expect(find.text('Entire recurring series removed.'), findsOneWidget);

      app.dispose();
    });
  });
}
