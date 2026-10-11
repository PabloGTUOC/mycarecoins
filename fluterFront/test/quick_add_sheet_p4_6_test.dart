import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/theme/app_theme.dart';
import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/daily_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';

class _FakeQuickAddApiClient extends ApiClient {
  List<Map<String, dynamic>> activities;
  final List<String> postCalls = [];
  final List<Map<String, dynamic>> postBodies = [];

  _FakeQuickAddApiClient({required this.activities});

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/activities')) {
      return {'activities': activities};
    }
    if (path.startsWith('/api/absences')) {
      return {'absences': <Map<String, dynamic>>[]};
    }
    if (path.startsWith('/api/personal-time')) {
      return {'requests': <Map<String, dynamic>>[]};
    }
    if (path.startsWith('/api/dashboard/')) {
      return {
        'members': <Map<String, dynamic>>[],
        'calendar': <Map<String, dynamic>>[],
        'objectsOfCare': <Map<String, dynamic>>[],
      };
    }
    if (path.startsWith('/api/marketplace/rewards/')) {
      return {'rewards': <Map<String, dynamic>>[], 'claimed': <Map<String, dynamic>>[]};
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
      return {'activity': newAct, 'warning': null};
    }
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
        child: child is DailyScreen ? child : Center(child: child),
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
      'tour.seen.checklist-dismissed': true,
    });
  });

  group('P4-6: Quick add sheet is one divided list', () {
    testWidgets(
        'shows all 3 titles in one container with 2 dividers, not separate cards',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeQuickAddApiClient(
        activities: [
          {
            'id': 101,
            'title': 'Bath',
            'type': 'care',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 30,
            'coin_value': 3,
          },
          {
            'id': 102,
            'title': 'Laundry',
            'type': 'household',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 45,
            'coin_value': 2,
          },
          {
            'id': 103,
            'title': 'Cooking',
            'type': 'household',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 60,
            'coin_value': 4,
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

      // Tap on future slot 10:00
      final hour10 = find.text('10:00');
      expect(hour10, findsOneWidget);
      final center10 = tester.getCenter(hour10);
      await tester.tapAt(Offset(center10.dx + 150, center10.dy));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Bottom sheet is visible
      expect(find.byType(BottomSheet), findsOneWidget);

      // All 3 titles are present
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('Bath')), findsOneWidget);
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('Laundry')), findsOneWidget);
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('Cooking')), findsOneWidget);

      // Exactly 2 dividers inside the bottom sheet
      final dividers = find.descendant(of: find.byType(BottomSheet), matching: find.byType(Divider));
      expect(dividers, findsNWidgets(2));

      // Task rows are not each wrapped in their own bordered Container
      // Only ONE surface container with border contains all three titles
      final sheetContainers = tester.widgetList<Container>(
        find.descendant(of: find.byType(BottomSheet), matching: find.byType(Container)),
      );
      final borderedSurfaceContainers = sheetContainers.where((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration) {
          return dec.color == AppColors.surface && dec.border != null;
        }
        return false;
      }).toList();
      expect(borderedSurfaceContainers.length, equals(1));

      // Tap on Bath -> calls schedule path and sheet closes
      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Bath')));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(api.postCalls.any((c) => c == '/api/activities/101/schedule'), isTrue);
    });

    testWidgets('tapping Time for me opens personal time sheet', (tester) async {
      tester.view.physicalSize = const Size(500, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeQuickAddApiClient(
        activities: [
          {
            'id': 101,
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

      final now = DateTime.parse('2026-10-06T08:00:00Z');
      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-06', now: now), app));
      await tester.pumpAndSettle();

      final hour10 = find.text('10:00');
      final center10 = tester.getCenter(hour10);
      await tester.tapAt(Offset(center10.dx + 150, center10.dy));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Time for me'), findsOneWidget);

      await tester.tap(find.text('Time for me'));
      await tester.pumpAndSettle();

      // Personal time dialog opened
      expect(find.text('Book personal time'), findsOneWidget);
    });
  });
}
