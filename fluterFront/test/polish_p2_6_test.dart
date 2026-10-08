import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/activities_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/widgets/family_circle.dart';
import 'package:carecoins_flutter/widgets/personal_time_dialog.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

class _FakePolishApiClient extends ApiClient {
  List<Map<String, dynamic>> templates;
  Map<String, dynamic> budget;
  List<Map<String, dynamic>> members;

  _FakePolishApiClient({
    this.templates = const [],
    this.budget = const {},
    this.members = const [],
  });

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/activities')) {
      return {'activities': templates};
    }
    if (path.contains('/budget')) {
      return budget;
    }
    if (path.contains('/members')) {
      return {'members': members};
    }
    if (path == '/api/me') {
      return {
        'user': {'id': 1, 'display_name': 'Caregiver'},
        'families': [
          {'family_id': 1, 'alias': 'Familia', 'coin_balance': 200, 'role': 'caregiver'}
        ],
        'actors': [],
      };
    }
    return {};
  }

  @override
  Future<dynamic> delete(String path, [Object? body]) async {
    return {'ok': true};
  }
}

Widget _app(Widget child, AppState app, [Locale locale = const Locale('en')]) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      locale: locale,
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
      'tour.seen.stats': true,
      'tour.seen.activities': true,
    });
  });

  group('P2-6 Item 1: Tasks catalogue status pills & overflow delete', () {
    testWidgets('shows status pill only for pending and rejected, overflow menu has delete',
        (tester) async {
      final fakeApi = _FakePolishApiClient(
        templates: [
          {
            'id': 1,
            'title': 'Washing dishes',
            'type': 'household',
            'duration_minutes': 30,
            'coin_value': 10,
            'status': 'approved',
            'is_template': true,
          },
          {
            'id': 2,
            'title': 'Park trip',
            'type': 'care',
            'duration_minutes': 60,
            'coin_value': 20,
            'status': 'pending',
            'is_template': true,
          },
          {
            'id': 3,
            'title': 'Roof repair',
            'type': 'household',
            'duration_minutes': 45,
            'coin_value': 15,
            'status': 'rejected',
            'is_template': true,
          },
        ],
      );

      final app = AppState(api: fakeApi)
        ..families = [
          {'family_id': 1, 'alias': 'Familia', 'coin_balance': 200, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Caregiver'};

      await tester.pumpWidget(_app(const ActivitiesScreen(), app));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('en'));

      // Approved template has NO status pill
      expect(find.text(l.badgeApproved), findsNothing);

      // Pending template has pending pill
      expect(find.text(l.badgePending), findsOneWidget);

      // Rejected template has rejected pill
      expect(find.text(l.badgeRejected), findsOneWidget);

      // No red trash icon directly in the rows
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);

      // Overflow menu (PopupMenuButton) is present on each row
      final menuFinders = find.byType(PopupMenuButton<String>);
      expect(menuFinders, findsNWidgets(3));

      // Tap the first overflow menu
      await tester.tap(menuFinders.first);
      await tester.pumpAndSettle();

      // "Delete" option appears in popup
      final deleteItem = find.text(l.deleteAction);
      expect(deleteItem, findsOneWidget);

      // Tap Delete in the menu -> confirmation dialog appears
      await tester.tap(deleteItem);
      await tester.pumpAndSettle();

      expect(find.text(l.deleteActivityTitle), findsOneWidget);
      expect(find.text(l.deleteActivityBody), findsOneWidget);

      // Cancel dismisses dialog
      await tester.tap(find.text(l.cancel));
      await tester.pumpAndSettle();

      expect(find.text(l.deleteActivityTitle), findsNothing);
    });
  });

  group('P2-6 Item 2: Me > Family circle edit mode for removing dependents', () {
    testWidgets('remove (x) appears only in explicit edit mode and toggles with Edit/Done',
        (tester) async {
      final fakeApi = _FakePolishApiClient(
        members: [
          {'id': 1, 'name': 'Mom', 'role': 'caregiver', 'avatar_url': null},
        ],
      );

      final app = AppState(api: fakeApi)
        ..families = [
          {'family_id': 1, 'alias': 'Familia', 'coin_balance': 200, 'role': 'caregiver'}
        ]
        ..actors = [
          {'id': 10, 'name': 'Baby Leo', 'actor_type': 'child', 'avatar_url': null},
        ]
        ..profile = {'id': 1, 'display_name': 'Mom'};

      await tester.pumpWidget(_app(const FamilyCircle(), app));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('en'));

      // Header shows "Edit" button
      expect(find.text(l.actionEdit), findsOneWidget);
      expect(find.text(l.actionDone), findsNothing);

      // Dependent card shows Leo, but NO close (x) button
      expect(find.text('Baby Leo'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      // Tap Edit
      await tester.tap(find.text(l.actionEdit));
      await tester.pumpAndSettle();

      // Header button toggles to "Done"
      expect(find.text(l.actionDone), findsOneWidget);
      expect(find.text(l.actionEdit), findsNothing);

      // Close (x) icon is now visible on the dependent card
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Tapping close (x) opens confirmation dialog
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text(l.removeDependentTitle), findsOneWidget);
      expect(find.text(l.removeDependentBody('Baby Leo')), findsOneWidget);

      // Cancel dismisses dialog
      await tester.tap(find.text(l.cancel));
      await tester.pumpAndSettle();
      expect(find.text(l.removeDependentTitle), findsNothing);

      // Tap Done
      await tester.tap(find.text(l.actionDone));
      await tester.pumpAndSettle();

      // Header shows "Edit" again, and close (x) icon is gone
      expect(find.text(l.actionEdit), findsOneWidget);
      expect(find.text(l.actionDone), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });
  });

  group('P2-6 Item 3: Budget progress indicator & labels', () {
    testWidgets('LinearProgressIndicator with labelled progress and renamed Scheduled or used',
        (tester) async {
      final fakeApi = _FakePolishApiClient(
        budget: {
          'monthlyBudget': 100,
          'remainingBudget': 70,
          'usedThisMonth': 30,
          'baseRatePerHour': 10,
        },
      );

      final app = AppState(api: fakeApi)
        ..families = [
          {'family_id': 1, 'alias': 'Familia', 'coin_balance': 200, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Caregiver'};

      await tester.pumpWidget(_app(const ActivitiesScreen(), app));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('en'));

      // Switch to Budget segment
      await tester.tap(find.text(l.tabBudget));
      await tester.pumpAndSettle();

      // Progress bar is LinearProgressIndicator
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Progress label shows "{used} of {pool} cc scheduled this month"
      expect(find.text(l.budgetScheduledProgress('30', '100')), findsOneWidget);

      // Three rows beneath are present
      expect(find.text(l.totalMonthlyPool), findsOneWidget);
      expect(find.text(l.scheduledUsed), findsOneWidget);
      expect(l.scheduledUsed, 'Scheduled or used');
      expect(find.text(l.estimatedRate), findsOneWidget);
    });
  });

  group('P2-6 Item 4: Material Rounded structural icons', () {
    test('activityTypeIcon maps type and category correctly to Material Rounded icons', () {
      expect(activityTypeIcon('care'), Icons.favorite_rounded);
      expect(activityTypeIcon('household'), Icons.restaurant_rounded);
      expect(activityTypeIcon('coverage'), Icons.home_rounded);
      expect(activityTypeIcon('sport', category: 'self'), Icons.fitness_center_rounded);
      expect(activityTypeIcon('social', category: 'self'), Icons.groups_rounded);
      expect(activityTypeIcon('rest', category: 'self'), Icons.self_improvement_rounded);
      expect(activityTypeIcon('appointment', category: 'self'), Icons.event_rounded);
      expect(activityTypeIcon('other', category: 'self'), Icons.auto_awesome_rounded);
      expect(personalTimeTypeIcon(null), Icons.auto_awesome_rounded);
    });

    testWidgets('personal time ChoiceChips render ActivityTypeIcon and no emoji glyph in text',
        (tester) async {
      final l = lookupAppLocalizations(const Locale('en'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Wrap(
              children: [
                for (final t in kPersonalTimeTypes)
                  ChoiceChip(
                    selected: t == 'sport',
                    avatar: ActivityTypeIcon(
                      type: t,
                      category: 'self',
                      size: 20,
                      iconSize: 13,
                    ),
                    label: Text(personalTimeTypeLabel(l, t)),
                  ),
              ],
            ),
          ),
        ),
      );

      // Check all 5 personal time types render ActivityTypeIcon
      expect(find.byType(ActivityTypeIcon), findsNWidgets(5));
      expect(find.byIcon(Icons.fitness_center_rounded), findsOneWidget);
      expect(find.byIcon(Icons.groups_rounded), findsOneWidget);
      expect(find.byIcon(Icons.self_improvement_rounded), findsOneWidget);
      expect(find.byIcon(Icons.event_rounded), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);

      // Labels contain text only, no emoji glyphs
      expect(find.text(l.ptTypeSport), findsOneWidget);
      expect(find.textContaining('🏃'), findsNothing);
      expect(find.textContaining('👥'), findsNothing);
      expect(find.textContaining('😴'), findsNothing);
      expect(find.textContaining('🩺'), findsNothing);
      expect(find.textContaining('✨'), findsNothing);
    });

    testWidgets('Tasks catalogue rows render ActivityTypeIcon without raw emoji',
        (tester) async {
      final fakeApi = _FakePolishApiClient(
        templates: [
          {
            'id': 1,
            'title': 'Baby massage',
            'type': 'care',
            'duration_minutes': 30,
            'coin_value': 10,
            'status': 'approved',
            'is_template': true,
          },
          {
            'id': 2,
            'title': 'Vacuuming',
            'type': 'household',
            'duration_minutes': 30,
            'coin_value': 10,
            'status': 'approved',
            'is_template': true,
          },
        ],
      );

      final app = AppState(api: fakeApi)
        ..families = [
          {'family_id': 1, 'alias': 'Familia', 'coin_balance': 200, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Caregiver'};

      await tester.pumpWidget(_app(const ActivitiesScreen(), app));
      await tester.pumpAndSettle();

      expect(find.byType(ActivityTypeIcon), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);
      expect(find.text('❤️'), findsNothing);
      expect(find.text('🍽️'), findsNothing);
    });
  });

  group('P2-6 Item 5: Localization across all 4 locales', () {
    test('actionEdit and actionDone in all locales', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final es = lookupAppLocalizations(const Locale('es'));
      final fr = lookupAppLocalizations(const Locale('fr'));
      final de = lookupAppLocalizations(const Locale('de'));

      expect(en.actionEdit, 'Edit');
      expect(es.actionEdit, 'Editar');
      expect(fr.actionEdit, 'Modifier');
      expect(de.actionEdit, 'Bearbeiten');

      expect(en.actionDone, 'Done');
      expect(es.actionDone, 'Listo');
      expect(fr.actionDone, 'Terminé');
      expect(de.actionDone, 'Fertig');
    });

    test('badgeRejected in all locales', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final es = lookupAppLocalizations(const Locale('es'));
      final fr = lookupAppLocalizations(const Locale('fr'));
      final de = lookupAppLocalizations(const Locale('de'));

      expect(en.badgeRejected, 'rejected');
      expect(es.badgeRejected, 'rechazada');
      expect(fr.badgeRejected, 'rejetée');
      expect(de.badgeRejected, 'abgelehnt');
    });

    test('scheduledUsed renamed in all locales', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final es = lookupAppLocalizations(const Locale('es'));
      final fr = lookupAppLocalizations(const Locale('fr'));
      final de = lookupAppLocalizations(const Locale('de'));

      expect(en.scheduledUsed, 'Scheduled or used');
      expect(es.scheduledUsed, 'Programado o usado');
      expect(fr.scheduledUsed, 'Programmé ou utilisé');
      expect(de.scheduledUsed, 'Geplant oder verbraucht');
    });

    test('budgetScheduledProgress in all locales', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final es = lookupAppLocalizations(const Locale('es'));
      final fr = lookupAppLocalizations(const Locale('fr'));
      final de = lookupAppLocalizations(const Locale('de'));

      expect(en.budgetScheduledProgress('20', '100'), '20 of 100 cc scheduled this month');
      expect(es.budgetScheduledProgress('20', '100'), '20 de 100 cc programadas este mes');
      expect(fr.budgetScheduledProgress('20', '100'), '20 sur 100 cc programmées ce mois-ci');
      expect(de.budgetScheduledProgress('20', '100'), '20 von 100 cc diesen Monat verplant');
    });
  });
}
