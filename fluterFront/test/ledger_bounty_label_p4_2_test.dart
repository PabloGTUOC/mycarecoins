import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/profile_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/theme/app_theme.dart';

class _FakeProfileApi extends ApiClient {
  List<Map<String, dynamic>> ledgerData = [];

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/me/notification-preferences')) {
      return <String, dynamic>{};
    }
    if (path.startsWith('/api/families/') &&
        path.contains('/deletion-requests')) {
      return {'deletionRequests': []};
    }
    if (path.startsWith('/api/me/ledger')) {
      return {'ledger': ledgerData};
    }
    if (path.startsWith('/api/activities')) return {'activities': []};
    if (path.startsWith('/api/absences')) return {'absences': []};
    if (path.startsWith('/api/personal-time')) return {'requests': []};
    if (path.startsWith('/api/dashboard/')) {
      return {'members': [], 'calendar': [], 'objectsOfCare': []};
    }
    if (path.startsWith('/api/marketplace/rewards/')) {
      return {'rewards': [], 'claimed': []};
    }
    if (path.startsWith('/api/stats')) {
      return {
        'activeCaregivers': ['Dad'],
        'kpis': {},
        'monthlyChart': [],
        'distribution': [],
      };
    }
    if (path == '/api/me') {
      return {
        'user': {'id': 1, 'display_name': 'Dad'},
        'families': [
          {
            'family_id': 101,
            'name': 'The Henderson Family',
            'role': 'caregiver',
            'alias': 'Dad',
            'coin_balance': 488,
          }
        ],
      };
    }
    return {};
  }

  @override
  Future<dynamic> post(String path, [Object? body]) async => {'success': true};

  @override
  Future<dynamic> put(String path, [Object? body]) async => {'success': true};

  @override
  Future<dynamic> delete(String path, [Object? body]) async => {'success': true};
}

Widget _wrap(Widget child, AppState app, {Locale locale = const Locale('en')}) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      locale: locale,
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

  group('P4-2: Bounty is an offer, not a fine', () {
    test('ARB files have new keys and no "not doing" or old keys', () {
      final arbFiles = [
        'lib/l10n/app_en.arb',
        'lib/l10n/app_es.arb',
        'lib/l10n/app_fr.arb',
        'lib/l10n/app_de.arb',
      ];

      for (final path in arbFiles) {
        final content = File(path).readAsStringSync();
        expect(content, contains('ledgerBountyOfferedT'),
            reason: '$path must contain ledgerBountyOfferedT');
        expect(content, contains('ledgerBountyOffered'),
            reason: '$path must contain ledgerBountyOffered');
        expect(content, isNot(contains('ledgerPaidNotDoing')),
            reason: '$path must not contain old key ledgerPaidNotDoing');
        expect(content, isNot(contains('ledgerBountyPaid')),
            reason: '$path must not contain old key ledgerBountyPaid');
        expect(content, isNot(contains('not doing')),
            reason: '$path must not contain old wording "not doing"');
      }
    });

    testWidgets('ProfileScreen.ledgerLabel returns "Offered for: {title}" and fallback across all locales',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          final lEn = lookupAppLocalizations(const Locale('en'));
          final lEs = lookupAppLocalizations(const Locale('es'));
          final lFr = lookupAppLocalizations(const Locale('fr'));
          final lDe = lookupAppLocalizations(const Locale('de'));

          // English
          expect(
            ProfileScreen.ledgerLabel(lEn, {
              'reason': 'bounty_escrow',
              'activity_title': 'Nap time',
            }),
            'Offered for: Nap time',
          );
          expect(
            ProfileScreen.ledgerLabel(lEn, {
              'reason': 'bounty_paid',
              'activity_title': 'Nap time',
            }),
            'Offered for: Nap time',
          );
          expect(
            ProfileScreen.ledgerLabel(lEn, {'reason': 'bounty_escrow'}),
            'Bounty offered',
          );
          expect(
            ProfileScreen.ledgerLabel(lEn, {'reason': 'bounty_paid'}),
            'Bounty offered',
          );

          // Spanish
          expect(
            ProfileScreen.ledgerLabel(lEs, {
              'reason': 'bounty_escrow',
              'activity_title': 'Nap time',
            }),
            'Ofrecido por: Nap time',
          );
          expect(
            ProfileScreen.ledgerLabel(lEs, {'reason': 'bounty_escrow'}),
            'Incentivo ofrecido',
          );

          // French
          expect(
            ProfileScreen.ledgerLabel(lFr, {
              'reason': 'bounty_escrow',
              'activity_title': 'Nap time',
            }),
            'Offert pour : Nap time',
          );
          expect(
            ProfileScreen.ledgerLabel(lFr, {'reason': 'bounty_escrow'}),
            'Prime offerte',
          );

          // German
          expect(
            ProfileScreen.ledgerLabel(lDe, {
              'reason': 'bounty_escrow',
              'activity_title': 'Nap time',
            }),
            'Angeboten für: Nap time',
          );
          expect(
            ProfileScreen.ledgerLabel(lDe, {'reason': 'bounty_escrow'}),
            'Bonus angeboten',
          );

          return const SizedBox.shrink();
        }),
      ));
      await tester.pumpAndSettle();
    });

    testWidgets('a ledger row with reason "bounty_escrow" and title "Nap time" renders "Offered for: Nap time"',
        (tester) async {
      tester.view.physicalSize = const Size(500, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeProfileApi();
      api.ledgerData = [
        {
          'activity_id': 1,
          'activity_title': 'Nap time',
          'reason': 'bounty_escrow',
          'amount': -2,
          'created_at': DateTime.now().toIso8601String(),
        },
      ];

      final app = AppState(api: api)
        ..families = [
          {
            'family_id': 101,
            'name': 'The Henderson Family',
            'role': 'caregiver',
            'alias': 'Dad',
            'coin_balance': 488,
          }
        ]
        ..profile = {'id': 1, 'display_name': 'Dad'};

      await tester.pumpWidget(_wrap(const ProfileScreen(), app));
      await tester.pumpAndSettle();

      // Renders "Offered for: Nap time"
      expect(find.text('Offered for: Nap time'), findsOneWidget);

      // The old wording "not doing" appears nowhere on the screen
      expect(find.textContaining('not doing'), findsNothing);
      expect(find.textContaining('You paid for not doing'), findsNothing);
      expect(find.textContaining('Bounty paid'), findsNothing);
    });
  });
}
