import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/activities_screen.dart';
import 'package:carecoins_flutter/screens/shell.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

class _FakeTasksApi extends ApiClient {
  List<Map<String, dynamic>> activities;

  _FakeTasksApi({this.activities = const []});

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/activities')) {
      return {'activities': activities};
    }
    if (path.startsWith('/api/absences')) {
      return {'absences': []};
    }
    if (path.startsWith('/api/personal-time')) {
      return {'requests': []};
    }
    if (path.startsWith('/api/dashboard/')) {
      return {'members': [], 'calendar': [], 'objectsOfCare': []};
    }
    if (path.startsWith('/api/marketplace/rewards/')) {
      return {'rewards': [], 'claimed': []};
    }
    if (path.startsWith('/api/stats')) {
      return {
        'kpis': {
          'total_lifetime_coins': 0,
          'total_lifetime_tasks': 0,
          'total_bounties_offered': 0,
          'total_rewards_claimed': 0,
        },
        'trend': [],
        'categories': [],
      };
    }
    if (path == '/api/me') {
      return {
        'user': {'id': 1, 'display_name': 'Parent'},
        'families': [
          {'family_id': 1, 'coin_balance': 200, 'role': 'caregiver'}
        ],
      };
    }
    return {};
  }

  @override
  Future<dynamic> post(String path, [Object? body]) async {
    return {'success': true};
  }
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
      'tour.seen.daily': true,
      'tour.seen.dashboard': true,
      'tour.seen.activities': true,
      'tour.seen.tasks': true,
      'tour.seen.checklist-dismissed': true,
    });
  });

  group('P3-4: Tasks: create is not the headline', () {
    testWidgets('IconButton with tooltip "New activity" exists in filter row and opens form',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeTasksApi(
        activities: [
          {
            'id': 1,
            'title': 'Brush teeth',
            'type': 'care',
            'is_template': true,
            'coin_value': 10,
            'status': 'approved',
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 200, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const ActivitiesScreen(), app));
      await tester.pumpAndSettle();

      // Filled tonal IconButton with tooltip "New activity" exists
      final addBtnFinder = find.byTooltip('New activity');
      expect(addBtnFinder, findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);

      // NO FilledButton or VButton with "New activity" or "+ New activity" text
      expect(find.widgetWithText(FilledButton, 'New activity'), findsNothing);
      expect(find.widgetWithText(VButton, 'New activity'), findsNothing);
      expect(find.widgetWithText(VButton, '+ New activity'), findsNothing);

      // Tapping the icon button opens the template creation sheet
      await tester.tap(addBtnFinder);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(VButton, 'Create activity template'), findsOneWidget);
    });

    testWidgets('no overflow at 320 px screen width (narrow phone)', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeTasksApi(
        activities: [
          {
            'id': 1,
            'title': 'Morning routine',
            'type': 'care',
            'is_template': true,
            'coin_value': 15,
            'status': 'approved',
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 200, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      // Test within Shell (with standard margin/padding)
      await tester.pumpWidget(_wrap(const Shell(initialIndex: 2), app));
      await tester.pumpAndSettle();

      // Rendered cleanly without overflow
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('New activity'), findsOneWidget);
      expect(find.text('Morning routine'), findsOneWidget);
    });

    testWidgets('empty catalogue keeps EmptyState action and has no headline buttons',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeTasksApi(activities: []);

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 200, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const ActivitiesScreen(), app));
      await tester.pumpAndSettle();

      // EmptyState action is still present
      expect(find.text('Create your first task'), findsOneWidget);

      // No headline buttons with "New activity"
      expect(find.widgetWithText(FilledButton, 'New activity'), findsNothing);
      expect(find.widgetWithText(VButton, '+ New activity'), findsNothing);

      // Add icon button is still present in filter row
      expect(find.byTooltip('New activity'), findsOneWidget);

      // Tapping EmptyState action opens form
      await tester.tap(find.text('Create your first task'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(VButton, 'Create activity template'), findsOneWidget);
    });
  });
}
