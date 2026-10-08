import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/profile_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/utils/activity_title.dart';
import 'package:carecoins_flutter/utils/formatters.dart';

class _FakeProfileApiClient extends ApiClient {
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
      return {'ledger': []};
    }
    if (path == '/api/me') {
      return {
        'user': {'id': 1, 'display_name': 'Parent'},
        'families': [
          {'family_id': 1, 'name': 'The Smiths', 'role': 'caregiver'}
        ],
      };
    }
    return {};
  }

  @override
  Future<dynamic> post(String path, [Object? body]) async {
    return {'success': true};
  }

  @override
  Future<dynamic> put(String path, [Object? body]) async {
    return {'success': true};
  }
}

Widget _wrap(Widget child, AppState app, [Locale locale = const Locale('en')]) {
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
  setUpAll(() async {
    await initializeDateFormatting();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('P2-4: 1. Coverage titles & displayTitle helper', () {
    testWidgets('localizes coverage titles and leaves other activities unchanged in all locales',
        (tester) async {
      for (final locale in AppLocalizations.supportedLocales) {
        late AppLocalizations l;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(builder: (context) {
              l = AppLocalizations.of(context);
              return const SizedBox();
            }),
          ),
        );
        await tester.pumpAndSettle();

        // Coverage with "Covering for " prefix is localized
        final coverageTask = {
          'category': 'care',
          'type': 'coverage',
          'title': 'Covering for Soccer Practice',
        };
        final expectedLocalized = l.coveringFor('Soccer Practice');
        expect(displayTitle(l, coverageTask), expectedLocalized);
        expect(expectedLocalized, isNotEmpty);
        expect(expectedLocalized, contains('Soccer Practice'));

        // Coverage without prefix remains unchanged
        final coverageNoPrefix = {
          'category': 'care',
          'type': 'coverage',
          'title': 'Babysitting',
        };
        expect(displayTitle(l, coverageNoPrefix), 'Babysitting');

        // Regular care activity with "Covering for " prefix remains UNCHANGED
        final careTask = {
          'category': 'care',
          'type': 'care',
          'title': 'Covering for Soccer Practice',
        };
        expect(displayTitle(l, careTask), 'Covering for Soccer Practice');

        // Household activity remains unchanged
        final householdTask = {
          'category': 'care',
          'type': 'household',
          'title': 'Dishwashing',
        };
        expect(displayTitle(l, householdTask), 'Dishwashing');

        // Personal time activity remains unchanged
        final selfTask = {
          'category': 'self',
          'type': 'sport',
          'title': 'Morning Jog',
        };
        expect(displayTitle(l, selfTask), 'Morning Jog');

        // Ledger row without type field but with coverage reason
        final ledgerCoverage = {
          'reason': 'coverage_earned',
          'activity_title': 'Covering for School Run',
        };
        expect(displayTitle(l, ledgerCoverage), l.coveringFor('School Run'));

        // Ledger row with standard activity_completed reason remains unchanged
        final ledgerStandard = {
          'reason': 'activity_completed',
          'activity_title': 'Covering for School Run',
        };
        expect(displayTitle(l, ledgerStandard), 'Covering for School Run');

        // Empty/null title returns empty string
        expect(displayTitle(l, {}), '');
      }
    });
  });

  group('P2-4: 2. Wallet ledger reasons mapping', () {
    testWidgets('maps every backend reason and reward redemption to a localized label, never raw code',
        (tester) async {
      late AppLocalizations l;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(builder: (context) {
            l = AppLocalizations.of(context);
            return const SizedBox();
          }),
        ),
      );
      await tester.pumpAndSettle();

      const backendReasons = [
        'activity_completed',
        'activity_reverted',
        'bounty_earned',
        'bounty_reverted',
        'bounty_refunded',
        'bounty_escrow',
        'bounty_paid',
        'coverage_earned',
        'coverage_reverted',
        'coverage_sweetener_paid',
        'coverage_sweetener_reverted',
        'coverage_sweetener_refunded',
        'coverage_sweetener_escrow',
        'monthly_distribution',
      ];

      // 1. Without activity_title
      for (final reason in backendReasons) {
        final label = ProfileScreen.ledgerLabel(l, {'reason': reason});
        expect(label, isNotEmpty, reason: 'Reason $reason must have a non-empty label');
        expect(label, isNot(equals(reason)),
            reason: 'Reason $reason must never return raw code');
      }

      // monthly_distribution specifically
      expect(
        ProfileScreen.ledgerLabel(l, {'reason': 'monthly_distribution'}),
        l.ledgerMonthlyDistribution,
      );
      expect(l.ledgerMonthlyDistribution, 'Monthly share');

      // 2. With activity_title
      for (final reason in backendReasons) {
        final label = ProfileScreen.ledgerLabel(
            l, {'reason': reason, 'activity_title': 'Dentist Appointment'});
        expect(label, isNotEmpty);
        expect(label, isNot(equals(reason)),
            reason: 'Reason $reason with title must never return raw code');
      }

      // 3. Reward redemptions: "Redeemed: {reward title}"
      final rewardLabel = ProfileScreen.ledgerLabel(
          l, {'reason': 'Redeemed: Hot Cocoa'});
      expect(rewardLabel, l.ledgerRedeemed('Hot Cocoa'));
      expect(rewardLabel, 'Redeemed: Hot Cocoa');

      // 4. Unknown fallback reason must never return raw reason code
      final unknownLabel =
          ProfileScreen.ledgerLabel(l, {'reason': 'unexpected_server_code'});
      expect(unknownLabel, l.ledgerMovement);
      expect(unknownLabel, isNot(equals('unexpected_server_code')));

      // Unknown reason with title returns title
      final unknownWithTitle = ProfileScreen.ledgerLabel(l, {
        'reason': 'unexpected_server_code',
        'activity_title': 'Special Event',
      });
      expect(unknownWithTitle, 'Special Event');
    });

    testWidgets('verifies monthly_distribution and redeemed strings across all 4 locales',
        (tester) async {
      final expectedMonthly = {
        'en': 'Monthly share',
        'es': 'Reparto mensual',
        'fr': 'Part mensuelle',
        'de': 'Monatlicher Anteil',
      };

      for (final locale in AppLocalizations.supportedLocales) {
        late AppLocalizations l;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(builder: (context) {
              l = AppLocalizations.of(context);
              return const SizedBox();
            }),
          ),
        );
        await tester.pumpAndSettle();

        final label =
            ProfileScreen.ledgerLabel(l, {'reason': 'monthly_distribution'});
        expect(label, expectedMonthly[locale.languageCode]);

        final redeemed =
            ProfileScreen.ledgerLabel(l, {'reason': 'Redeemed: Ice Cream'});
        expect(redeemed, contains('Ice Cream'));
        expect(redeemed, isNot(startsWith('raw_')));
      }
    });
  });

  group('P2-4: 3. Me tab: no family ID pill in family banner', () {
    testWidgets('family banner shows name and member alias but no FAMILY ID or database id pill',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeProfileApiClient();
      final app = AppState(api: api)
        ..families = [
          {
            'family_id': 98765,
            'name': 'The Henderson Family',
            'role': 'caregiver',
            'alias': 'Dad',
          }
        ]
        ..profile = {'id': 1, 'display_name': 'Dad'};

      await tester.pumpWidget(_wrap(const ProfileScreen(), app));
      await tester.pumpAndSettle();

      // Banner shows family name and member alias
      expect(find.text('The Henderson Family · Dad'), findsOneWidget);

      // Must NOT find "FAMILY ID" or the raw family id number
      expect(find.text('FAMILY ID'), findsNothing);
      expect(find.text('98765'), findsNothing);
      expect(find.textContaining('FAMILY ID'), findsNothing);
    });
  });

  group('P2-4: 4. Charts: month axis labels via DateFormat.yMMM', () {
    test('formats ISO month string in English and Spanish without showing raw 2026-08', () {
      final enLabel = formatChartMonth('2026-08', 'en');
      expect(enLabel, 'Aug 2026');
      expect(enLabel, isNot(contains('2026-08')));

      final esLabel = formatChartMonth('2026-08', 'es');
      expect(esLabel, 'ago 2026');
      expect(esLabel, isNot(contains('2026-08')));

      final frLabel = formatChartMonth('2026-08', 'fr');
      expect(frLabel, 'août 2026');

      final deLabel = formatChartMonth('2026-08', 'de');
      expect(deLabel, 'Aug. 2026');
    });

    test('handles fallback for invalid or unparseable input', () {
      expect(formatChartMonth('invalid'), 'invalid');
      expect(formatChartMonth(''), '');
    });
  });

  group('P2-4: 5. Em dashes: no em dash or spaced double hyphen in any ARB value', () {
    final arbs = Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb'))
        .toList();

    test('all 4 ARB files exist', () {
      expect(arbs.length, 4);
    });

    for (final file in arbs) {
      test('${file.uri.pathSegments.last} contains zero em dashes (—) and zero spaced double hyphens ( -- )', () {
        final content = file.readAsStringSync();
        final map = json.decode(content) as Map<String, dynamic>;
        final violations = <String>[];

        map.forEach((key, value) {
          if (key.startsWith('@') || value is! String) return;

          if (value.contains('—')) {
            violations.add('$key contains em dash (—): "$value"');
          }
          if (value.contains(' -- ')) {
            violations.add('$key contains spaced double hyphen ( -- ): "$value"');
          }
        });

        expect(
          violations,
          isEmpty,
          reason: 'Violations found in ${file.path}:\n${violations.join('\n')}',
        );
      });
    }
  });
}
