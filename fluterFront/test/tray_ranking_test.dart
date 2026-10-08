import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/daily_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/utils/tray_ranking.dart';

class _FakeTrayApi extends ApiClient {
  final List<Map<String, dynamic>> activities;

  _FakeTrayApi({this.activities = const []});

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
      return {
        'members': [],
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
          {'family_id': 1, 'coin_balance': 100, 'role': 'caregiver'}
        ],
      };
    }
    return {};
  }
}

Widget _wrap(Widget child, AppState app) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ScaffoldMessenger(child: child),
    ),
  );
}

void main() {
  final now = DateTime.parse('2026-10-08T12:00:00Z');

  group('P2-12: pure function rankTemplates', () {
    test("someone else's instances don't count", () {
      final templates = [
        {'id': 1, 'title': 'Dishes', 'type': 'household'},
        {'id': 2, 'title': 'Bath', 'type': 'care'},
      ];
      final activities = [
        {
          'id': 101,
          'title': 'Dishes',
          'type': 'household',
          'category': 'care',
          'assigned_to': 2, // someone else
          'starts_at': '2026-10-07T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
        {
          'id': 102,
          'title': 'Bath',
          'type': 'care',
          'category': 'care',
          'assigned_to': 1, // current user
          'starts_at': '2026-10-07T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
      ];

      final result = rankTemplates(
        templates: templates,
        activities: activities,
        userId: '1',
        now: now,
      );

      // Bath was used by user 1, Dishes was not used by user 1.
      expect(result.ordered.map((t) => t['title']).toList(), ['Bath', 'Dishes']);
    });

    test("instances older than 60 days don't count", () {
      final templates = [
        {'id': 1, 'title': 'OldTask', 'type': 'household'},
        {'id': 2, 'title': 'RecentTask', 'type': 'care'},
        {'id': 3, 'title': 'FutureFarTask', 'type': 'household'},
        {'id': 4, 'title': 'FutureNearTask', 'type': 'care'},
      ];
      final activities = [
        // 61 days ago -> older than 60 days, must not count
        {
          'id': 101,
          'title': 'OldTask',
          'type': 'household',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': now.subtract(const Duration(days: 61)).toIso8601String(),
          'is_template': false,
          'status': 'completed',
        },
        // 30 days ago -> within 60 days, counts
        {
          'id': 102,
          'title': 'RecentTask',
          'type': 'care',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': now.subtract(const Duration(days: 30)).toIso8601String(),
          'is_template': false,
          'status': 'completed',
        },
        // 15 days in future -> > 14 days, must not count
        {
          'id': 103,
          'title': 'FutureFarTask',
          'type': 'household',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': now.add(const Duration(days: 15)).toIso8601String(),
          'is_template': false,
          'status': 'pending',
        },
        // 5 days in future -> <= 14 days, counts
        {
          'id': 104,
          'title': 'FutureNearTask',
          'type': 'care',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': now.add(const Duration(days: 5)).toIso8601String(),
          'is_template': false,
          'status': 'pending',
        },
      ];

      final result = rankTemplates(
        templates: templates,
        activities: activities,
        userId: '1',
        now: now,
      );

      final orderedTitles = result.ordered.map((t) => t['title']).toList();
      // FutureNearTask and RecentTask are used (count 1). FutureNearTask has later timestamp.
      expect(orderedTitles.take(2).toList(), ['FutureNearTask', 'RecentTask']);
      // OldTask and FutureFarTask are unused (count 0), sorted alphabetically
      expect(orderedTitles.skip(2).toList(), ['FutureFarTask', 'OldTask']);
    });

    test("coverage/self/rejected don't count", () {
      final templates = [
        {'id': 1, 'title': 'CoverageTask', 'type': 'coverage'},
        {'id': 2, 'title': 'SelfCategoryTask', 'type': 'care'},
        {'id': 3, 'title': 'SelfTypeTask', 'type': 'self'},
        {'id': 4, 'title': 'RejectedTask', 'type': 'care'},
        {'id': 5, 'title': 'ValidCareTask', 'type': 'care'},
      ];
      final activities = [
        // type == 'coverage'
        {
          'id': 101,
          'title': 'CoverageTask',
          'type': 'coverage',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': '2026-10-07T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
        // category == 'self' (e.g. Time for me)
        {
          'id': 102,
          'title': 'SelfCategoryTask',
          'type': 'care',
          'category': 'self',
          'assigned_to': '1',
          'starts_at': '2026-10-07T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
        // type == 'self'
        {
          'id': 103,
          'title': 'SelfTypeTask',
          'type': 'self',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': '2026-10-07T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
        // status == 'rejected'
        {
          'id': 104,
          'title': 'RejectedTask',
          'type': 'care',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': '2026-10-07T10:00:00Z',
          'is_template': false,
          'status': 'rejected',
        },
        // Valid care task
        {
          'id': 105,
          'title': 'ValidCareTask',
          'type': 'care',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': '2026-10-07T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
      ];

      final result = rankTemplates(
        templates: templates,
        activities: activities,
        userId: '1',
        now: now,
      );

      // Only ValidCareTask is counted as used
      expect(result.ordered.first['title'], 'ValidCareTask');
      final unused = result.ordered.skip(1).map((t) => t['title']).toList();
      expect(unused, containsAll(['CoverageTask', 'SelfCategoryTask', 'SelfTypeTask', 'RejectedTask']));
    });

    test('title+type both must match', () {
      final templates = [
        {'id': 1, 'title': 'Clean', 'type': 'care'},
        {'id': 2, 'title': 'Clean', 'type': 'household'},
        {'id': 3, 'title': 'Other', 'type': 'household'},
      ];
      final activities = [
        // Matches Clean + household only
        {
          'id': 101,
          'title': 'Clean',
          'type': 'household',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': '2026-10-07T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
      ];

      final result = rankTemplates(
        templates: templates,
        activities: activities,
        userId: '1',
        now: now,
      );

      // Clean (household) is first because it matched both title and type
      expect(result.ordered.first['title'], 'Clean');
      expect(result.ordered.first['type'], 'household');
      // Clean (care) was not matched
      expect(result.ordered[1]['title'], 'Clean');
      expect(result.ordered[1]['type'], 'care');
    });

    test('tie-breaks: count desc, recent desc, title case-insensitive; unused after used', () {
      final templates = [
        {'title': 'Zebra', 'type': 'care'}, // count 3
        {'title': 'Yacht', 'type': 'care'}, // count 2, recent 1d ago
        {'title': 'Apple', 'type': 'care'}, // count 2, recent 5d ago
        {'title': 'banana', 'type': 'care'}, // count 2, recent 5d ago
        {'title': 'Cherry', 'type': 'care'}, // count 2, recent 5d ago
        {'title': 'Zoo', 'type': 'care'}, // count 0
        {'title': 'alligator', 'type': 'care'}, // count 0
        {'title': 'Bear', 'type': 'care'}, // count 0
      ];

      final activities = [
        // Zebra: 3 instances
        for (int i = 0; i < 3; i++)
          {
            'title': 'Zebra',
            'type': 'care',
            'category': 'care',
            'assigned_to': '1',
            'starts_at': '2026-10-01T10:00:00Z',
            'is_template': false,
            'status': 'completed',
          },
        // Yacht: 2 instances, most recent 2026-10-07
        {
          'title': 'Yacht',
          'type': 'care',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': '2026-10-07T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
        {
          'title': 'Yacht',
          'type': 'care',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': '2026-10-02T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
        // Apple: 2 instances, most recent 2026-10-03
        {
          'title': 'Apple',
          'type': 'care',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': '2026-10-03T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
        {
          'title': 'Apple',
          'type': 'care',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': '2026-10-02T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
        // banana: 2 instances, most recent 2026-10-03
        {
          'title': 'banana',
          'type': 'care',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': '2026-10-03T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
        {
          'title': 'banana',
          'type': 'care',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': '2026-10-01T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
        // Cherry: 2 instances, most recent 2026-10-03
        {
          'title': 'Cherry',
          'type': 'care',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': '2026-10-03T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
        {
          'title': 'Cherry',
          'type': 'care',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': '2026-10-01T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
      ];

      final result = rankTemplates(
        templates: templates,
        activities: activities,
        userId: '1',
        now: now,
      );

      final titles = result.ordered.map((t) => t['title']).toList();
      expect(titles, [
        'Zebra', // count 3
        'Yacht', // count 2, latest Oct 7
        'Apple', // count 2, latest Oct 3, title 'Apple'
        'banana', // count 2, latest Oct 3, title 'banana'
        'Cherry', // count 2, latest Oct 3, title 'Cherry'
        'alligator', // count 0, title 'alligator'
        'Bear', // count 0, title 'Bear'
        'Zoo', // count 0, title 'Zoo'
      ]);
    });

    test('under 3 distinct used -> full list in quick', () {
      final templates = [
        {'title': 'T1', 'type': 'care'},
        {'title': 'T2', 'type': 'care'},
        {'title': 'T3', 'type': 'care'},
        {'title': 'T4', 'type': 'care'},
      ];
      final activities = [
        {
          'title': 'T1',
          'type': 'care',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': '2026-10-07T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
        {
          'title': 'T2',
          'type': 'care',
          'category': 'care',
          'assigned_to': '1',
          'starts_at': '2026-10-07T10:00:00Z',
          'is_template': false,
          'status': 'completed',
        },
      ];

      final result = rankTemplates(
        templates: templates,
        activities: activities,
        userId: '1',
        now: now,
      );

      // Only 2 distinct used templates -> quick set is the full ordered list (4 templates)
      expect(result.quick.length, 4);
      expect(result.quick.map((t) => t['title']).toList(), ['T1', 'T2', 'T3', 'T4']);
    });

    test('3+ distinct used -> used only, capped at 8', () {
      // 10 templates
      final templates = [
        for (int i = 1; i <= 10; i++)
          {'title': 'Task $i', 'type': 'care'},
      ];

      // 9 distinct templates have instances (Task 1 through Task 9)
      final activities = [
        for (int i = 1; i <= 9; i++)
          {
            'title': 'Task $i',
            'type': 'care',
            'category': 'care',
            'assigned_to': '1',
            // earlier i has later date so Task 1 is most recent
            'starts_at': now.subtract(Duration(days: i)).toIso8601String(),
            'is_template': false,
            'status': 'completed',
          },
      ];

      final result = rankTemplates(
        templates: templates,
        activities: activities,
        userId: '1',
        now: now,
      );

      // Total ordered contains all 10 templates
      expect(result.ordered.length, 10);

      // Distinct used is 9 (>= 3) -> quick shows used only, capped at kTrayQuickMax (8)
      expect(result.quick.length, 8);
      expect(result.quick.map((t) => t['title']).toList(), [
        'Task 1',
        'Task 2',
        'Task 3',
        'Task 4',
        'Task 5',
        'Task 6',
        'Task 7',
        'Task 8',
      ]);
      // Task 9 (used but capped out) and Task 10 (unused) are NOT in quick
      expect(result.quick.any((t) => t['title'] == 'Task 9'), isFalse);
      expect(result.quick.any((t) => t['title'] == 'Task 10'), isFalse);

      // Also verify with 4 templates where exactly 3 are used
      final fourTemplates = [
        {'title': 'A', 'type': 'care'},
        {'title': 'B', 'type': 'care'},
        {'title': 'C', 'type': 'care'},
        {'title': 'D', 'type': 'care'},
      ];
      final threeUsedActivities = [
        for (final title in ['A', 'B', 'C'])
          {
            'title': title,
            'type': 'care',
            'category': 'care',
            'assigned_to': '1',
            'starts_at': now.toIso8601String(),
            'is_template': false,
            'status': 'completed',
          },
      ];
      final resultFour = rankTemplates(
        templates: fourTemplates,
        activities: threeUsedActivities,
        userId: '1',
        now: now,
      );
      // Quick shows only the 3 used templates; D is omitted
      expect(resultFour.quick.map((t) => t['title']).toList(), ['A', 'B', 'C']);
    });
  });

  group('P2-12: widget test - tray quick set vs all tasks', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'tour.seen.welcome': true,
        'tour.seen.daily': true,
        'tour.seen.dashboard': true,
        'tour.seen.checklist-dismissed': true,
      });
    });

    testWidgets(
        'with 3+ used templates the collapsed tray shows only those chips and All tasks still lists an unused one',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeTrayApi(
        activities: [
          // 4 templates in catalogue
          {
            'id': 10,
            'title': 'Cooking',
            'type': 'household',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 60,
            'coin_value': 5,
          },
          {
            'id': 20,
            'title': 'Bath',
            'type': 'care',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 30,
            'coin_value': 3,
          },
          {
            'id': 30,
            'title': 'Storytime',
            'type': 'care',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 20,
            'coin_value': 2,
          },
          {
            'id': 40,
            'title': 'Laundry',
            'type': 'household',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 45,
            'coin_value': 2,
          },
          // 3 distinct used templates for user 1 (Cooking, Bath, Storytime).
          // Laundry is unused.
          {
            'id': 101,
            'title': 'Cooking',
            'type': 'household',
            'category': 'care',
            'assigned_to': 1,
            'starts_at': '2026-10-07T08:00:00Z',
            'is_template': false,
            'status': 'completed',
          },
          {
            'id': 102,
            'title': 'Bath',
            'type': 'care',
            'category': 'care',
            'assigned_to': 1,
            'starts_at': '2026-10-07T09:00:00Z',
            'is_template': false,
            'status': 'completed',
          },
          {
            'id': 103,
            'title': 'Storytime',
            'type': 'care',
            'category': 'care',
            'assigned_to': 1,
            'starts_at': '2026-10-07T19:00:00Z',
            'is_template': false,
            'status': 'completed',
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      final testNow = DateTime.parse('2026-10-08T10:00:00Z');
      await tester.pumpWidget(
        _wrap(DailyScreen(date: '2026-10-08', now: testNow), app),
      );
      await tester.pumpAndSettle();

      // In collapsed tray: 3 used templates are shown as chips.
      expect(find.text('Cooking'), findsOneWidget);
      expect(find.text('Bath'), findsOneWidget);
      expect(find.text('Storytime'), findsOneWidget);

      // Unused template 'Laundry' is NOT in the collapsed tray.
      expect(find.text('Laundry'), findsNothing);

      // Tap "All tasks" button to expand the tray
      final allTasksButton = find.text('All tasks');
      expect(allTasksButton, findsOneWidget);
      await tester.tap(allTasksButton);
      await tester.pumpAndSettle();

      // In expanded tray: "Laundry" is listed!
      expect(find.text('Laundry'), findsOneWidget);

      // The 3 used tasks are also still present in expanded tray
      expect(find.text('Cooking'), findsOneWidget);
      expect(find.text('Bath'), findsOneWidget);
      expect(find.text('Storytime'), findsOneWidget);
    });
  });
}
