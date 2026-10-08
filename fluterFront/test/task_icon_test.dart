import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/activities_screen.dart';
import 'package:carecoins_flutter/screens/daily_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/theme/app_theme.dart';
import 'package:carecoins_flutter/utils/task_icon.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

class _FakeApiClient extends ApiClient {
  List<Map<String, dynamic>> activities;

  _FakeApiClient({this.activities = const []});

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
    if (path.startsWith('/api/absences')) {
      return {'absences': <dynamic>[]};
    }
    if (path.startsWith('/api/personal-time')) {
      return {'requests': <dynamic>[]};
    }
    if (path.startsWith('/api/dashboard/')) {
      return {
        'members': <dynamic>[],
        'calendar': <dynamic>[],
        'objectsOfCare': <dynamic>[],
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
}

Widget _wrap(Widget child, AppState app) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      theme: buildAppTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ScaffoldMessenger(child: child is DailyScreen ? child : Scaffold(body: child)),
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

  group('P3-8: taskIconFor pure unit tests', () {
    test('all 21 starter titles from backend/src/db/defaultActivities.js map to intended icons', () {
      // HOUSEHOLD_ACTIVITIES (7)
      expect(taskIconFor('Breakfast prep'), Icons.free_breakfast_rounded);
      expect(taskIconFor('Lunch prep'), Icons.lunch_dining_rounded);
      expect(taskIconFor('Dinner prep'), Icons.dinner_dining_rounded);
      expect(taskIconFor('Grocery shopping'), Icons.shopping_cart_rounded);
      expect(taskIconFor('Laundry'), Icons.local_laundry_service_rounded);
      expect(taskIconFor('House cleaning'), Icons.cleaning_services_rounded);
      expect(taskIconFor('Dishes / kitchen cleanup'), Icons.soap_rounded);

      // CHILD_ACTIVITIES (9)
      expect(taskIconFor('Morning routine'), Icons.wb_sunny_rounded);
      expect(taskIconFor('Daycare / school drop-off'), Icons.school_rounded);
      expect(taskIconFor('Daycare / school pick-up'), Icons.backpack_rounded);
      expect(taskIconFor('Nap time supervision'), Icons.hotel_rounded);
      expect(taskIconFor('Outdoor play / park'), Icons.park_rounded);
      expect(taskIconFor('Bath time'), Icons.bathtub_rounded);
      expect(taskIconFor('Bedtime routine'), Icons.bedtime_rounded);
      expect(taskIconFor('Night wake-up'), Icons.nights_stay_rounded);
      expect(taskIconFor('Homework help'), Icons.menu_book_rounded);

      // PET_ACTIVITIES (3)
      expect(taskIconFor('Morning walk'), Icons.directions_walk_rounded);
      expect(taskIconFor('Evening walk'), Icons.directions_walk_rounded);
      expect(taskIconFor('Pet feeding'), Icons.pets_rounded);

      // GENERIC_CARE_ACTIVITIES (2)
      expect(taskIconFor('Doctor / appointment accompany'), Icons.medical_services_rounded);
      expect(taskIconFor('Medication reminder'), Icons.medication_rounded);
    });

    test('Spanish, French, and German titles map correctly', () {
      // Spanish
      expect(taskIconFor('Baño'), Icons.bathtub_rounded);
      expect(taskIconFor('Cena'), Icons.dinner_dining_rounded);
      expect(taskIconFor('Hacer la compra'), Icons.shopping_cart_rounded);

      // French: rule 3 "chien" wins over rule 24 "promenade"
      expect(taskIconFor('Promenade du chien'), Icons.pets_rounded);
      expect(taskIconFor('Promenade au parc'), Icons.directions_walk_rounded);
      expect(taskIconFor('Ménage'), Icons.cleaning_services_rounded);
      expect(taskIconFor('Petit-déjeuner'), Icons.free_breakfast_rounded);

      // German
      expect(taskIconFor('Hausaufgaben'), Icons.menu_book_rounded);
      expect(taskIconFor('Draußen spielen'), Icons.park_rounded);
      expect(taskIconFor('Bügeln'), Icons.iron_rounded);
      expect(taskIconFor('Wäsche waschen'), Icons.local_laundry_service_rounded);
    });

    test('accents are stripped before matching', () {
      expect(taskIconFor('médicament'), Icons.medication_rounded);
      expect(taskIconFor('clínica'), Icons.medical_services_rounded);
      expect(taskIconFor('réveil'), Icons.nights_stay_rounded);
      expect(taskIconFor('pañal'), Icons.baby_changing_station_rounded);
      expect(taskIconFor('dîner'), Icons.dinner_dining_rounded);
      expect(taskIconFor('küche'), Icons.soap_rounded);
      expect(taskIconFor('BAÑO'), Icons.bathtub_rounded);
    });

    test('word boundary matching: snap != nap, bathe matches bath', () {
      // "snap" contains "nap" inside the word, should NOT match
      expect(taskIconFor('snap'), isNull);
      expect(taskIconFor('ginger snap'), isNull);

      // "nap" at word start matches
      expect(taskIconFor('nap'), Icons.hotel_rounded);
      expect(taskIconFor('taking a nap'), Icons.hotel_rounded);

      // "bath" matches "bath time" and "bathe"
      expect(taskIconFor('bath time'), Icons.bathtub_rounded);
      expect(taskIconFor('bathe'), Icons.bathtub_rounded);
    });

    test('rule order priorities', () {
      // "Morning walk" -> walk (24) wins over morning (28)
      expect(taskIconFor('Morning walk'), Icons.directions_walk_rounded);
      // "Daycare / school pick-up" -> pick-up (4) wins over school (5)
      expect(taskIconFor('Daycare / school pick-up'), Icons.backpack_rounded);
      // "Night wake-up" -> night (9)
      expect(taskIconFor('Night wake-up'), Icons.nights_stay_rounded);
    });

    test('unknown title or empty returns null', () {
      expect(taskIconFor(null), isNull);
      expect(taskIconFor(''), isNull);
      expect(taskIconFor('   '), isNull);
      expect(taskIconFor('completely unknown chore xyz'), isNull);
    });
  });

  group('P3-8: activityTypeIcon / ActivityTypeIcon tests', () {
    test('resolves task icon for care/household and falls back for unknown', () {
      // Known care/household task
      expect(activityTypeIcon('care', category: 'care', title: 'Bath time'), Icons.bathtub_rounded);
      expect(activityTypeIcon('household', category: 'care', title: 'Breakfast prep'), Icons.free_breakfast_rounded);
      expect(activityTypeIcon('care', category: null, title: 'Bath time'), Icons.bathtub_rounded);

      // Unknown title falls back to base type icon
      expect(activityTypeIcon('care', category: 'care', title: 'Unknown task xyz'), Icons.favorite_rounded);
      expect(activityTypeIcon('household', category: 'care', title: 'Unknown task xyz'), Icons.restaurant_rounded);
      expect(activityTypeIcon('care', category: 'care', title: null), Icons.favorite_rounded);

      // Coverage always shows home_rounded regardless of title
      expect(activityTypeIcon('coverage', category: 'care', title: 'Bath time'), Icons.home_rounded);
      expect(activityTypeIcon('coverage', category: 'coverage', title: 'Bath time'), Icons.home_rounded);

      // Self / personal time always uses personal time type icon
      expect(activityTypeIcon('rest', category: 'self', title: 'Bath time'), Icons.self_improvement_rounded);
      expect(activityTypeIcon('sport', category: 'self', title: 'Bath time'), Icons.fitness_center_rounded);
    });

    testWidgets('ActivityTypeIcon widget renders matching task icon and keeps type colors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ActivityTypeIcon(type: 'care', category: 'care', title: 'Bath time'),
                ActivityTypeIcon(type: 'household', category: 'care', title: 'Breakfast prep'),
                ActivityTypeIcon(type: 'care', category: 'care', title: 'Unknown chore'),
                ActivityTypeIcon(type: 'coverage', category: 'care', title: 'Bath time'),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.bathtub_rounded), findsOneWidget);
      expect(find.byIcon(Icons.free_breakfast_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    });
  });

  group('P3-8: Widget integration in DailyScreen and ActivitiesScreen', () {
    testWidgets('care template titled "Bath time" shows Icons.bathtub_rounded in tray chip and unknown shows category icon', (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeApiClient(
        activities: [
          {
            'id': 10,
            'title': 'Bath time',
            'type': 'care',
            'category': 'care',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 30,
            'coin_value': 3,
          },
          {
            'id': 20,
            'title': 'Custom chore 123',
            'type': 'care',
            'category': 'care',
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
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const DailyScreen(), app));
      await tester.pumpAndSettle();

      // "Bath time" chip displays bathtub_rounded
      expect(find.text('Bath time'), findsOneWidget);
      expect(find.byIcon(Icons.bathtub_rounded), findsOneWidget);

      // "Custom chore 123" unknown title displays favorite_rounded (care fallback)
      expect(find.text('Custom chore 123'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });

    testWidgets('care template titled "Bath time" shows Icons.bathtub_rounded in catalogue row', (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeApiClient(
        activities: [
          {
            'id': 1,
            'title': 'Bath time',
            'type': 'care',
            'category': 'care',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 30,
            'coin_value': 5,
          },
          {
            'id': 2,
            'title': 'Unknown task xyz',
            'type': 'household',
            'category': 'care',
            'is_template': true,
            'status': 'approved',
            'duration_minutes': 45,
            'coin_value': 10,
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const ActivitiesScreen(), app));
      await tester.pumpAndSettle();

      // "Bath time" row displays bathtub_rounded
      expect(find.text('Bath time'), findsOneWidget);
      expect(find.byIcon(Icons.bathtub_rounded), findsOneWidget);

      // "Unknown task xyz" household template displays restaurant_rounded (household fallback)
      expect(find.text('Unknown task xyz'), findsOneWidget);
      expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);
    });
  });

  group('short keywords match whole words only', () {
    test('a short keyword inside a longer word does not fire', () {
      expect(taskIconFor("Little one's bath"), Icons.bathtub_rounded); // not "lit"
      expect(taskIconFor('Clean the bedroom'), Icons.cleaning_services_rounded); // not "bed"
      expect(taskIconFor('Return the shopping cart'), Icons.shopping_cart_rounded); // not "car"
      expect(taskIconFor('Get ready for school'), Icons.school_rounded); // not "read"
      expect(taskIconFor('Play catch'), Icons.park_rounded); // not "cat"
      expect(taskIconFor('Pillow fort'), isNull); // not "pill"
    });

    test('plurals and -ing forms still match', () {
      expect(taskIconFor('Walk the dogs'), Icons.pets_rounded);
      expect(taskIconFor('Reading time'), Icons.auto_stories_rounded);
      expect(taskIconFor('Ironing'), Icons.iron_rounded);
      expect(taskIconFor('Naps'), Icons.hotel_rounded);
    });
  });
}
