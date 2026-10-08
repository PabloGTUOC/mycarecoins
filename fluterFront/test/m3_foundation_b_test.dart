import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/activities_screen.dart';
import 'package:carecoins_flutter/screens/daily_screen.dart';
import 'package:carecoins_flutter/screens/marketplace_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/theme/app_theme.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

class FakeM3bApiClient extends ApiClient {
  final List<String> getCalls = [];
  final List<String> postCalls = [];
  final List<String> patchCalls = [];

  @override
  Future<dynamic> get(String path) async {
    getCalls.add(path);
    if (path.startsWith('/api/activities/day/')) {
      return {
        'activities': [
          {
            'id': 'act-sched-1',
            'title': 'School run',
            'starts_at': null,
            'duration_minutes': 60,
            'coin_value': 20,
            'status': 'pending',
            'type': 'care',
            'category': 'care',
            'is_template': false,
          }
        ]
      };
    }
    if (path.startsWith('/api/activities')) {
      return {
        'activities': [
          {
            'id': 'tpl-1',
            'title': 'Dishwashing',
            'type': 'household',
            'duration_minutes': 30,
            'coin_value': 10,
            'status': 'approved',
            'is_template': true,
          }
        ]
      };
    }
    if (path.contains('/budget')) {
      return {
        'monthlyBudget': 1000,
        'remainingBudget': 800,
        'usedThisMonth': 200,
        'baseRatePerHour': 20,
      };
    }
    if (path.startsWith('/api/absences')) return {'absences': []};
    if (path.startsWith('/api/personal-time')) return {'requests': []};
    if (path.startsWith('/api/marketplace/rewards/')) {
      return {
        'rewards': [
          {
            'id': 'rew-1',
            'title': 'Ice cream',
            'description': 'One scoop',
            'cost': 15,
            'uses': 0,
          }
        ],
        'claimed': [
          {
            'id': 'claim-1',
            'title': 'Board game night',
            'buyer_name': 'Sam',
            'cost': 25,
            'redeemed_at': '2026-10-07T12:00:00Z',
          }
        ],
      };
    }
    if (path == '/api/me') {
      return {
        'user': {'id': 1, 'display_name': 'Me'},
        'families': [
          {'family_id': 1, 'alias': 'Familia', 'coin_balance': 250, 'role': 'caregiver'}
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
    return {'success': true};
  }
}

Widget _app(Widget child, AppState app, {ThemeData? theme}) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      theme: theme ?? buildAppTheme(),
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
      'tour.seen.marketplace': true,
      'tour.seen.profile': true,
      'tour.seen.checklist-dismissed': true,
    });
  });

  group('P2-3b: Material 3 VButton rendering per type', () {
    testWidgets('primary renders FilledButton', (tester) async {
      final fakeApi = FakeM3bApiClient();
      final app = AppState(api: fakeApi);

      await tester.pumpWidget(_app(
        VButton(
          type: VButtonType.primary,
          onPressed: () {},
          child: const Text('Primary'),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Primary'), findsOneWidget);
    });

    testWidgets('secondary renders FilledButton (tonal)', (tester) async {
      final fakeApi = FakeM3bApiClient();
      final app = AppState(api: fakeApi);

      await tester.pumpWidget(_app(
        VButton(
          type: VButtonType.secondary,
          onPressed: () {},
          child: const Text('Secondary'),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Secondary'), findsOneWidget);
    });

    testWidgets('outline renders OutlinedButton', (tester) async {
      final fakeApi = FakeM3bApiClient();
      final app = AppState(api: fakeApi);

      await tester.pumpWidget(_app(
        VButton(
          type: VButtonType.outline,
          onPressed: () {},
          child: const Text('Outline'),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.text('Outline'), findsOneWidget);
    });

    testWidgets('danger renders FilledButton with error color', (tester) async {
      final fakeApi = FakeM3bApiClient();
      final app = AppState(api: fakeApi);

      await tester.pumpWidget(_app(
        VButton(
          type: VButtonType.danger,
          onPressed: () {},
          child: const Text('Danger'),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      final filledFinder = find.byType(FilledButton);
      expect(filledFinder, findsOneWidget);
      final button = tester.widget<FilledButton>(filledFinder);
      expect(button.style?.backgroundColor?.resolve({}), AppColors.danger);
    });

    testWidgets('block expands button to full width', (tester) async {
      final fakeApi = FakeM3bApiClient();
      final app = AppState(api: fakeApi);

      await tester.pumpWidget(_app(
        Center(
          child: SizedBox(
            width: 300,
            child: VButton(
              block: true,
              onPressed: () {},
              child: const Text('Block'),
            ),
          ),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      final sizedBoxFinder = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == double.infinity,
      );
      expect(sizedBoxFinder, findsOneWidget);
    });

    testWidgets('disabled disables button', (tester) async {
      final fakeApi = FakeM3bApiClient();
      final app = AppState(api: fakeApi);
      var tapped = false;

      await tester.pumpWidget(_app(
        VButton(
          disabled: true,
          onPressed: () => tapped = true,
          child: const Text('Disabled'),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      final filledFinder = find.byType(FilledButton);
      final button = tester.widget<FilledButton>(filledFinder);
      expect(button.onPressed, isNull);

      await tester.tap(find.text('Disabled'));
      await tester.pumpAndSettle();
      expect(tapped, isFalse);
    });
  });

  group('P2-3b: SegmentedTabs renders Material SegmentedButton<int>', () {
    testWidgets('renders SegmentedButton and switches selection on tap',
        (tester) async {
      final fakeApi = FakeM3bApiClient();
      final app = AppState(api: fakeApi);
      int selected = 0;

      await tester.pumpWidget(_app(
        StatefulBuilder(builder: (context, setState) {
          return SegmentedTabs(
            tabs: const ['Tab A', 'Tab B'],
            selected: selected,
            onChanged: (i) => setState(() => selected = i),
          );
        }),
        app,
      ));
      await tester.pumpAndSettle();

      final segmentedFinder = find.byType(SegmentedButton<int>);
      expect(segmentedFinder, findsOneWidget);
      final segWidget = tester.widget<SegmentedButton<int>>(segmentedFinder);
      expect(segWidget.showSelectedIcon, isFalse);
      expect(segWidget.selected, {0});

      await tester.tap(find.text('Tab B'));
      await tester.pumpAndSettle();

      final segWidgetAfter = tester.widget<SegmentedButton<int>>(segmentedFinder);
      expect(segWidgetAfter.selected, {1});
    });
  });

  group('P2-3b: VCard renders Material Card', () {
    testWidgets('renders Card with optional title', (tester) async {
      final fakeApi = FakeM3bApiClient();
      final app = AppState(api: fakeApi);

      await tester.pumpWidget(_app(
        const VCard(
          title: 'Card Title',
          child: Text('Card Content'),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Card Title'), findsOneWidget);
      expect(find.text('Card Content'), findsOneWidget);
    });
  });

  group('P2-3b: Time entry in DailyScreen uses showTimePicker', () {
    testWidgets('schedule flow opens showTimePicker and no dropdowns',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeApi = FakeM3bApiClient();
      final app = AppState(api: fakeApi)
        ..families = [
          {'family_id': 1, 'alias': 'Familia', 'coin_balance': 250, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_app(const DailyScreen(isTab: true), app));
      await tester.pumpAndSettle();

      // Open task sheet via FAB
      // Phones have no FAB since the tray: "All tasks" expands the library.
      final allTasks = find.text('All tasks');
      expect(allTasks, findsOneWidget);
      await tester.tap(allTasks);
      await tester.pumpAndSettle();

      // Pick Dishwashing template
      expect(find.text('Dishwashing'), findsOneWidget);
      await tester.tap(find.text('Dishwashing'));
      await tester.pumpAndSettle();

      // showTimePicker opens TimePickerDialog (not DropdownButtonFormField)
      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);

      // Confirm time picker
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Verify schedule call was posted
      expect(fakeApi.postCalls.any((c) => c.contains('/schedule')), isTrue);

      // Flush toast auto-dismiss timer
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('P2-3b: Rewards in MarketplaceScreen', () {
    testWidgets('has no SegmentedTabs, has Create tonal button, opens sheet',
        (tester) async {
      final fakeApi = FakeM3bApiClient();
      final app = AppState(api: fakeApi)
        ..families = [
          {'family_id': 1, 'alias': 'Familia', 'coin_balance': 250, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_app(const MarketplaceScreen(), app));
      await tester.pumpAndSettle();

      // No SegmentedTabs in MarketplaceScreen
      expect(find.byType(SegmentedTabs), findsNothing);
      expect(find.byType(SegmentedButton<int>), findsNothing);

      // Store reward and history are in the same scrolling list
      expect(find.text('Ice cream'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.textContaining('Board game night'), findsOneWidget);

      // Create a reward button at top for caregivers
      final createBtn = find.widgetWithText(FilledButton, 'Create a reward');
      expect(createBtn, findsOneWidget);

      // Tap Create a reward opens modal bottom sheet
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      // Sheet is open with create form
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Create a reward'),
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(VButton, 'Create reward'), findsOneWidget);
    });
  });

  group('P2-3b: Tasks in ActivitiesScreen', () {
    testWidgets('has 2-segment tabs (Catalogue & Budget) and New activity opens sheet',
        (tester) async {
      final fakeApi = FakeM3bApiClient();
      final app = AppState(api: fakeApi)
        ..families = [
          {'family_id': 1, 'alias': 'Familia', 'coin_balance': 250, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_app(const ActivitiesScreen(), app));
      await tester.pumpAndSettle();

      // SegmentedTabs has only Catalogue and Budget
      final segFinder = find.byType(SegmentedButton<int>);
      expect(segFinder, findsOneWidget);
      final segWidget = tester.widget<SegmentedButton<int>>(segFinder);
      expect(segWidget.segments.length, 2);
      expect(find.text('Catalogue'), findsOneWidget);
      expect(find.text('Budget'), findsOneWidget);

      // New activity is a tonal button at the top of Catalogue
      final newActBtn = find.widgetWithText(FilledButton, 'New activity');
      expect(newActBtn, findsOneWidget);

      // Tapping New activity opens modal bottom sheet
      await tester.tap(newActBtn);
      await tester.pumpAndSettle();

      // Sheet is open with new activity form
      expect(find.widgetWithText(VButton, 'Create activity template'), findsOneWidget);

      // Dismiss sheet
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // Switch to Budget segment
      await tester.tap(find.text('Budget'));
      await tester.pumpAndSettle();

      expect(find.text('Family budget health'), findsOneWidget);
    });
  });
}
