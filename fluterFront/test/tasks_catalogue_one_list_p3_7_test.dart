import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/activities_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/theme/app_theme.dart';

class _FakeActivitiesApi extends ApiClient {
  List<Map<String, dynamic>> activities;
  String? deletedPath;

  _FakeActivitiesApi({this.activities = const []});

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

  @override
  Future<dynamic> delete(String path, [Object? body]) async {
    deletedPath = path;
    return {'success': true};
  }
}

Widget _wrap(Widget child, AppState app) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      theme: buildAppTheme(),
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
      'tour.seen.profile': true,
      'tour.seen.checklist-dismissed': true,
    });
  });

  group('P3-7: Tasks catalogue as one list', () {
    testWidgets('renders templates in ONE bordered container with dividers between rows',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeActivitiesApi(activities: [
        {
          'id': 1,
          'title': 'Brush teeth',
          'type': 'care',
          'is_template': true,
          'duration_minutes': 10,
          'coin_value': 5,
          'status': 'approved',
        },
        {
          'id': 2,
          'title': 'Clean kitchen',
          'type': 'household',
          'is_template': true,
          'duration_minutes': 30,
          'coin_value': 15,
          'status': 'approved',
        },
        {
          'id': 3,
          'title': 'Do laundry',
          'type': 'household',
          'is_template': true,
          'duration_minutes': 45,
          'coin_value': 20,
          'status': 'approved',
        },
      ]);

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const ActivitiesScreen(), app));
      await tester.pumpAndSettle();

      // Find the bordered container holding the templates Column
      final containerFinder = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final decoration = w.decoration;
        if (decoration is! BoxDecoration) return false;
        return decoration.color == AppColors.surface &&
            decoration.border != null &&
            decoration.borderRadius == BorderRadius.circular(AppRadii.md) &&
            w.child is Column;
      });

      expect(containerFinder, findsOneWidget);

      final containerWidget = tester.widget<Container>(containerFinder);
      final column = containerWidget.child as Column;

      // 3 template rows + 2 dividers between them = 5 children
      expect(column.children.length, 5);

      // Child 1 is Divider, Child 3 is Divider
      expect(column.children[1], isA<Divider>());
      expect(column.children[3], isA<Divider>());

      final divider = column.children[1] as Divider;
      expect(divider.height, 1);
      expect(divider.thickness, 1);
      expect(divider.color, AppColors.border);

      // Check row padding is 16 horizontal, 12 vertical
      expect(column.children[0], isA<Padding>());
      final paddingWidget = column.children[0] as Padding;
      expect(
        paddingWidget.padding,
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      );
    });

    testWidgets('with all-recurring templates no repeat icon is shown',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeActivitiesApi(activities: [
        {
          'id': 1,
          'title': 'Morning routine',
          'type': 'care',
          'is_template': true,
          'is_recurrent': true,
          'status': 'approved',
        },
        {
          'id': 2,
          'title': 'Evening routine',
          'type': 'care',
          'is_template': true,
          'is_recurrent': true,
          'status': 'approved',
        },
      ]);

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const ActivitiesScreen(), app));
      await tester.pumpAndSettle();

      // No repeat icon rendered
      expect(find.byIcon(Icons.repeat_rounded), findsNothing);
      expect(
        find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Repeats'),
        findsNothing,
      );
    });

    testWidgets('with mixed templates repeat icon shows ONLY on recurring rows',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeActivitiesApi(activities: [
        {
          'id': 1,
          'title': 'Daily Walk',
          'type': 'care',
          'is_template': true,
          'is_recurrent': true,
          'status': 'approved',
        },
        {
          'id': 2,
          'title': 'Fix fence',
          'type': 'household',
          'is_template': true,
          'is_recurrent': false,
          'status': 'approved',
        },
      ]);

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const ActivitiesScreen(), app));
      await tester.pumpAndSettle();

      // Exactly one repeat icon
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);

      // Verify it's on Daily Walk row with Semantics
      final dailyWalkRow = find.ancestor(
        of: find.text('Daily Walk'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: dailyWalkRow, matching: find.byIcon(Icons.repeat_rounded)),
        findsOneWidget,
      );

      // Fix fence row does NOT have the repeat icon
      final fixFenceRow = find.ancestor(
        of: find.text('Fix fence'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: fixFenceRow, matching: find.byIcon(Icons.repeat_rounded)),
        findsNothing,
      );
    });

    testWidgets('the ⋮ delete menu still works', (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeActivitiesApi(activities: [
        {
          'id': 42,
          'title': 'Trash task',
          'type': 'household',
          'is_template': true,
          'is_recurrent': false,
          'status': 'approved',
        },
      ]);

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const ActivitiesScreen(), app));
      await tester.pumpAndSettle();

      // Open the overflow menu
      final menuBtn = find.byIcon(Icons.more_vert_rounded);
      expect(menuBtn, findsOneWidget);
      await tester.tap(menuBtn);
      await tester.pumpAndSettle();

      // Tap Delete in menu
      final deleteItem = find.text('Delete');
      expect(deleteItem, findsOneWidget);
      await tester.tap(deleteItem);
      await tester.pumpAndSettle();

      // Confirmation dialog appears
      expect(find.byType(AlertDialog), findsOneWidget);

      // Confirm deletion in dialog
      final confirmBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Delete'),
      );
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // API delete was called with the activity ID
      expect(api.deletedPath, '/api/activities/42');

      // Flush toast timer
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
