import 'dart:io';

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

class _FakeApiClient extends ApiClient {
  List<Map<String, dynamic>> activities;

  _FakeApiClient({this.activities = const []});

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/activities')) {
      return {'activities': activities};
    }
    if (path.contains('/budget')) {
      return {
        'monthlyBudget': 1000,
        'remainingBudget': 800,
        'usedThisMonth': 200,
        'baseRatePerHour': 20,
      };
    }
    return {};
  }
}

Widget _wrap(Widget child, AppState app, {Locale locale = const Locale('en')}) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('P3-3: Scan test for glyphs', () {
    test('no 🔁 or 🪙 in any lib/**/*.dart except landing_screen.dart', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith('landing_screen.dart'));

      final violations = <String>[];
      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        if (content.contains('🪙')) {
          violations.add('${file.path} contains 🪙');
        }
        if (content.contains('🔁')) {
          violations.add('${file.path} contains 🔁');
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  group('P3-3: Recurrence icon and semantics', () {
    testWidgets('DayActivityBlock renders repeat icon with "Repeats" semantics label on recurring block',
        (tester) async {
      final activity = {
        'id': 1,
        'title': 'Morning Medicine',
        'is_recurrent': true,
        'status': 'pending',
        'type': 'care',
        'category': 'care',
        'starts_at': '2026-10-08T09:00:00Z',
        'duration_minutes': 30,
        'assigned_to': 2,
        'assigned_to_name': 'Ben',
        'coin_value': 20,
      };

      final api = _FakeApiClient();
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 140,
          height: 80,
          child: DayActivityBlock(activity: activity),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      // Recurrence icon renders with repeat_rounded
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);

      final icon = tester.widget<Icon>(find.byIcon(Icons.repeat_rounded));
      expect(icon.size, 13);
      expect(icon.color, AppColors.textSecondary);

      // Semantics label is "Repeats"
      final semanticsFinder = find.descendant(
        of: find.byType(DayActivityBlock),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Repeats',
        ),
      );
      expect(semanticsFinder, findsOneWidget);
      expect(
        find.descendant(of: semanticsFinder, matching: find.byIcon(Icons.repeat_rounded)),
        findsOneWidget,
      );
    });

    testWidgets('ActivitiesScreen renders repeat icon with "Repeats" semantics label on recurring activity',
        (tester) async {
      final api = _FakeApiClient(activities: [
        {
          'id': 'tpl-1',
          'title': 'Daily Walk',
          'type': 'care',
          'category': 'care',
          'duration_minutes': 45,
          'coin_value': 15,
          'status': 'approved',
          'is_recurrent': true,
          'is_template': true,
        },
      ]);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(const ActivitiesScreen(), app));
      await tester.pumpAndSettle();

      expect(find.text('Daily Walk'), findsOneWidget);
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);

      final icon = tester.widget<Icon>(find.byIcon(Icons.repeat_rounded));
      expect(icon.size, 16);
      expect(icon.color, AppColors.textSecondary);

      final semanticsFinder = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Repeats',
      );
      expect(semanticsFinder, findsOneWidget);
      expect(
        find.descendant(of: semanticsFinder, matching: find.byIcon(Icons.repeat_rounded)),
        findsOneWidget,
      );
    });

    testWidgets('Recurrence icon uses localized label in Spanish (Se repite)',
        (tester) async {
      final activity = {
        'id': 1,
        'title': 'Medicina',
        'is_recurrent': true,
        'status': 'pending',
        'type': 'care',
        'category': 'care',
        'starts_at': '2026-10-08T09:00:00Z',
        'duration_minutes': 30,
        'assigned_to': 2,
        'assigned_to_name': 'Ben',
        'coin_value': 20,
      };

      final api = _FakeApiClient();
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 140,
          height: 80,
          child: DayActivityBlock(activity: activity),
        ),
        app,
        locale: const Locale('es'),
      ));
      await tester.pumpAndSettle();

      final semanticsFinder = find.descendant(
        of: find.byType(DayActivityBlock),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Se repite',
        ),
      );
      expect(semanticsFinder, findsOneWidget);
      expect(
        find.descendant(of: semanticsFinder, matching: find.byIcon(Icons.repeat_rounded)),
        findsOneWidget,
      );
    });
  });

  group('P3-3: Coin formatting (N cc without 🪙)', () {
    testWidgets('DayActivityBlock formats coins as N cc with space and no emoji',
        (tester) async {
      final activity = {
        'id': 1,
        'title': 'Feed cat',
        'is_recurrent': false,
        'status': 'pending',
        'type': 'care',
        'category': 'care',
        'starts_at': '2026-10-08T09:00:00Z',
        'duration_minutes': 30,
        'assigned_to': 2,
        'assigned_to_name': 'Ben',
        'coin_value': 25,
      };

      final api = _FakeApiClient();
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 140,
          height: 80,
          child: DayActivityBlock(activity: activity),
        ),
        app,
      ));
      await tester.pumpAndSettle();

      expect(find.text('25 cc'), findsOneWidget);
      expect(find.textContaining('🪙'), findsNothing);
    });
  });

  group('P3-3: ARB sentence casing and recurrence text', () {
    test('English ARB has sentence case and clean recurrence keys', () {
      final l = lookupAppLocalizations(const Locale('en'));
      expect(l.recurringCheckbox, 'This is a recurring activity');
      expect(l.faqRepeatA, isNot(contains('🔁')));
      expect(l.repeatsLabel, 'Repeats');
      expect(l.dashTitle, 'Family hub');
      expect(l.dashActiveMembers, 'Active family members');
      expect(l.totalBalance, 'Total balance');
      expect(l.coinsUnit, 'Coins');
      expect(l.pendingInvitations, 'Pending invitations');
      expect(l.createAccountTitle, 'Create CareCoins account');
      expect(l.step1Title, '1. Family details');
      expect(l.step3Title, '3. Objects of care');
      expect(l.step4Title, '4. Starter tasks');
    });

    test('Spanish ARB has sentence case and clean recurrence keys', () {
      final l = lookupAppLocalizations(const Locale('es'));
      expect(l.recurringCheckbox, 'Es una actividad recurrente');
      expect(l.faqRepeatA, isNot(contains('🔁')));
      expect(l.repeatsLabel, 'Se repite');
      expect(l.dashTitle, 'Centro familiar');
      expect(l.totalBalance, 'Saldo total');
      expect(l.coinsUnit, 'Monedas');
      expect(l.pendingInvitations, 'Invitaciones pendientes');
      expect(l.goToToday, 'Ir a Hoy');
    });

    test('French ARB has sentence case and clean recurrence keys', () {
      final l = lookupAppLocalizations(const Locale('fr'));
      expect(l.recurringCheckbox, "C'est une activité récurrente");
      expect(l.faqRepeatA, isNot(contains('🔁')));
      expect(l.repeatsLabel, 'Se répète');
      expect(l.dashTitle, 'Espace famille');
      expect(l.totalBalance, 'Solde total');
      expect(l.coinsUnit, 'Pièces');
      expect(l.pendingInvitations, 'Invitations en attente');
      expect(l.goToToday, "Aller à Aujourd'hui");
    });

    test('German ARB preserves noun capitals and has clean recurrence keys', () {
      final l = lookupAppLocalizations(const Locale('de'));
      expect(l.recurringCheckbox, 'Dies ist eine wiederkehrende Aufgabe');
      expect(l.faqRepeatA, isNot(contains('🔁')));
      expect(l.repeatsLabel, 'Wiederholt sich');
      expect(l.totalBalance, 'Gesamtsaldo');
      expect(l.coinsUnit, 'Münzen');
      expect(l.pendingInvitations, 'Ausstehende Einladungen');
      expect(l.goToToday, 'Zu Heute gehen');
    });
  });
}
