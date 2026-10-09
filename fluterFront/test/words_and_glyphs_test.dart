import 'dart:convert';
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

    test('no emoji in ARB values (ranges U+1F300–U+1FAFF and U+2600–U+27BF except ✓)', () {
      final arbFiles = [
        'lib/l10n/app_en.arb',
        'lib/l10n/app_es.arb',
        'lib/l10n/app_fr.arb',
        'lib/l10n/app_de.arb',
      ];

      final violations = <String>[];
      for (final path in arbFiles) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path must exist');
        final jsonMap = json.decode(file.readAsStringSync()) as Map<String, dynamic>;

        for (final entry in jsonMap.entries) {
          if (entry.key.startsWith('@')) continue;
          final value = entry.value;
          if (value is String) {
            for (final rune in value.runes) {
              if (rune == 0x2713) continue; // ✓ is allowed
              if ((rune >= 0x1F300 && rune <= 0x1FAFF) ||
                  (rune >= 0x2600 && rune <= 0x27BF)) {
                violations.add(
                  '$path: key "${entry.key}" contains emoji "${String.fromCharCode(rune)}" (U+${rune.toRadixString(16).toUpperCase()}) in "$value"',
                );
                break;
              }
            }
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('no 📷 in any lib/**/*.dart', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final violations = <String>[];
      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        if (content.contains('📷')) {
          violations.add('${file.path} contains 📷');
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('no character in U+1F300–U+1FAFF in lib/**/*.dart except landing_screen and pre-existing feature glyphs', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      const allowedFiles = {
        'landing_screen.dart',
        'personal_time_dialog.dart',
        'dashboard_screen.dart',
        'stats_screen.dart',
        'marketplace_screen.dart',
        'push_service.dart',
      };

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !allowedFiles.any((a) => f.path.endsWith(a)));

      final violations = <String>[];
      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        for (final rune in content.runes) {
          if (rune >= 0x1F300 && rune <= 0x1FAFF) {
            violations.add('${file.path} contains U+${rune.toRadixString(16).toUpperCase()} (${String.fromCharCode(rune)})');
            break;
          }
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
        {
          'id': 'tpl-2',
          'title': 'One-off Chore',
          'type': 'care',
          'category': 'care',
          'duration_minutes': 20,
          'coin_value': 10,
          'status': 'approved',
          'is_recurrent': false,
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
      expect(l.dashMembers, 'Members');
      expect(l.roleCaregiver, 'Caregiver');
      expect(l.roleMember, 'Member');
      expect(l.yourBalance, 'Your balance');
      expect(l.seeFamilyStats, 'See family stats');
      expect(l.sectionYou, 'You');
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
      expect(l.dashMembers, 'Miembros');
      expect(l.roleCaregiver, 'Cuidador');
      expect(l.roleMember, 'Miembro');
      expect(l.yourBalance, 'Tu saldo');
      expect(l.seeFamilyStats, 'Ver estadísticas de la familia');
      expect(l.sectionYou, 'Tú');
      expect(l.pendingInvitations, 'Invitaciones pendientes');
      expect(l.goToToday, 'Ir a Hoy');
    });

    test('French ARB has sentence case and clean recurrence keys', () {
      final l = lookupAppLocalizations(const Locale('fr'));
      expect(l.recurringCheckbox, "C'est une activité récurrente");
      expect(l.faqRepeatA, isNot(contains('🔁')));
      expect(l.repeatsLabel, 'Se répète');
      expect(l.dashTitle, 'Espace famille');
      expect(l.dashMembers, 'Membres');
      expect(l.roleCaregiver, 'Aidant');
      expect(l.roleMember, 'Membre');
      expect(l.yourBalance, 'Votre solde');
      expect(l.seeFamilyStats, 'Voir les statistiques de la famille');
      expect(l.sectionYou, 'Vous');
      expect(l.pendingInvitations, 'Invitations en attente');
      expect(l.goToToday, "Aller à Aujourd'hui");
    });

    test('German ARB preserves noun capitals and has clean recurrence keys', () {
      final l = lookupAppLocalizations(const Locale('de'));
      expect(l.recurringCheckbox, 'Dies ist eine wiederkehrende Aufgabe');
      expect(l.faqRepeatA, isNot(contains('🔁')));
      expect(l.repeatsLabel, 'Wiederholt sich');
      expect(l.dashMembers, 'Mitglieder');
      expect(l.roleCaregiver, 'Betreuende Person');
      expect(l.roleMember, 'Mitglied');
      expect(l.yourBalance, 'Dein Guthaben');
      expect(l.seeFamilyStats, 'Familienstatistiken ansehen');
      expect(l.sectionYou, 'Du');
      expect(l.pendingInvitations, 'Ausstehende Einladungen');
      expect(l.goToToday, 'Zu Heute gehen');
    });
  });
}
