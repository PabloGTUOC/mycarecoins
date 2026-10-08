import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/shell.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

class _FakeHubApi extends ApiClient {
  List<Map<String, dynamic>> activities;
  List<Map<String, dynamic>> requests;
  List<Map<String, dynamic>> members;
  List<Map<String, dynamic>> objectsOfCare;

  _FakeHubApi({
    this.activities = const [],
    this.requests = const [],
    this.members = const [],
    this.objectsOfCare = const [],
  });

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/activities')) {
      return {'activities': activities};
    }
    if (path.startsWith('/api/absences')) {
      return {'absences': []};
    }
    if (path.startsWith('/api/personal-time')) {
      return {'requests': requests};
    }
    if (path.startsWith('/api/dashboard/')) {
      return {
        'members': members,
        'calendar': [],
        'objectsOfCare': objectsOfCare,
      };
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
          {'family_id': 1, 'coin_balance': 500, 'role': 'caregiver'}
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
      home: child,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tour.seen.welcome': true,
      'tour.seen.daily': true,
      'tour.seen.dashboard': true,
      'tour.seen.checklist-dismissed': true,
    });
  });

  group('P3-2: Family hub compact members list', () {
    testWidgets('renders members in one container, ordered by name, with roles and balances',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Fixture returned ordered by balance descending: Charlie (500), Bob (250), Alice (100)
      final api = _FakeHubApi(
        members: [
          {
            'user_id': 3,
            'name': 'Charlie',
            'role': 'member',
            'coin_balance': 500,
            'status': 'active',
          },
          {
            'user_id': 2,
            'name': 'Bob',
            'role': 'member',
            'coin_balance': 250,
            'status': 'active',
          },
          {
            'user_id': 1,
            'name': 'Alice',
            'role': 'caregiver',
            'coin_balance': 100,
            'status': 'active',
          },
        ],
        objectsOfCare: [
          {
            'id': 102,
            'name': 'Zoe',
          },
          {
            'id': 101,
            'name': 'Ben',
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 850, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Alice'};

      await tester.pumpWidget(_wrap(const Shell(initialIndex: 1), app));
      await tester.pumpAndSettle();

      // Section title is "Members"
      expect(find.text('Members'), findsOneWidget);
      expect(find.text('Active family members'), findsNothing);

      // Verify active members are ordered alphabetically by name:
      // Alice (Caregiver, 100 cc) -> Bob (Member, 250 cc) -> Charlie (Member, 500 cc)
      // Dependents follow ordered alphabetically: Ben (cared for) -> Zoe (cared for)
      final alicePos = tester.getTopLeft(find.text('Alice')).dy;
      final bobPos = tester.getTopLeft(find.text('Bob')).dy;
      final charliePos = tester.getTopLeft(find.text('Charlie')).dy;
      final benPos = tester.getTopLeft(find.text('Ben')).dy;
      final zoePos = tester.getTopLeft(find.text('Zoe')).dy;

      expect(alicePos < bobPos, isTrue, reason: 'Alice before Bob');
      expect(bobPos < charliePos, isTrue, reason: 'Bob before Charlie');
      expect(charliePos < benPos, isTrue, reason: 'Charlie before Ben');
      expect(benPos < zoePos, isTrue, reason: 'Ben before Zoe');

      // Role subtitles
      expect(find.text('Caregiver'), findsOneWidget);
      expect(find.text('Member'), findsNWidgets(2));
      expect(find.text('Cared for'), findsNWidgets(2));

      // Balance pills for active members only
      expect(find.text('100 cc'), findsOneWidget);
      expect(find.text('250 cc'), findsOneWidget);
      expect(find.text('500 cc'), findsOneWidget);

      // Dependents do not have balance pills
      // 3 active member pills inside the member list
      expect(find.byType(PillBadge), findsNWidgets(3));

      // Hairline dividers between all 5 rows (4 dividers)
      expect(find.byType(Divider), findsNWidgets(4));
    });

    testWidgets('pending approvals stay under the members container', (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeHubApi(
        members: [
          {
            'user_id': 1,
            'name': 'Alice',
            'role': 'caregiver',
            'coin_balance': 100,
            'status': 'active',
          },
          {
            'user_id': 4,
            'name': 'Pending Pete',
            'role': 'member',
            'coin_balance': 0,
            'status': 'pending',
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 100, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Alice'};

      await tester.pumpWidget(_wrap(const Shell(initialIndex: 1), app));
      await tester.pumpAndSettle();

      expect(find.text('Pending approval'), findsOneWidget);
      expect(find.text('Pending Pete'), findsOneWidget);
    });
  });

  group('P3-2: Duplicated cover and offers sections removed from hub', () {
    testWidgets('no cover or offers sections on Family hub even when requests and bounties exist',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      final nowStr = now.toIso8601String();

      final api = _FakeHubApi(
        members: [
          {
            'user_id': 1,
            'name': 'Alice',
            'role': 'caregiver',
            'coin_balance': 100,
            'status': 'active',
          },
        ],
        requests: [
          {
            'id': 99,
            'requester_id': 2,
            'requester_name': 'Bob',
            'requested_of': 1,
            'status': 'pending',
            'type': 'sports',
            'title': 'Soccer practice',
            'starts_at': nowStr,
            'ends_at': nowStr,
            'baseline_coins': 10,
            'sweetener_coins': 5,
          },
        ],
        activities: [
          {
            'id': 10,
            'title': 'Mow lawn',
            'status': 'open',
            'bounty_amount': 25,
            'starts_at': nowStr,
          },
        ],
      );

      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 100, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Alice'};

      await tester.pumpWidget(_wrap(const Shell(initialIndex: 1), app));
      await tester.pumpAndSettle();

      // Cover request section is NOT displayed on Family hub
      expect(find.text('Asked you to cover'), findsNothing);
      expect(find.text('Decline'), findsNothing);
      expect(find.text('Accept'), findsNothing);
      expect(find.textContaining('for covering'), findsNothing);

      // Offers section is NOT displayed on Family hub
      expect(find.text('Task offers & bribes'), findsNothing);
      expect(find.text('1 open'), findsNothing);

      // BUT the greeting indicates needs-you and links to Today
      expect(find.textContaining('Something on Today needs you.'), findsOneWidget);
      expect(find.text('Go to Today'), findsOneWidget);

      // And the KPI card still accounts for the bounty offer
      expect(find.text('Open bounties'), findsOneWidget);
      expect(find.text('25 cc up for grabs'), findsOneWidget);
    });
  });

  group('P3-2: Code cleanliness scan', () {
    test('dead code widgets and keys are absent from dashboard_screen.dart', () {
      final code = File('lib/screens/dashboard_screen.dart').readAsStringSync();
      expect(code.contains('_MemberCard'), isFalse, reason: '_MemberCard removed');
      expect(code.contains('_CoverRequestCard'), isFalse, reason: '_CoverRequestCard removed');
      expect(code.contains('dashCoverTitle'), isFalse, reason: 'dashCoverTitle removed');
      expect(code.contains('dashOffersTitle'), isFalse, reason: 'dashOffersTitle removed');
      expect(code.contains('offersOpenCount'), isFalse, reason: 'offersOpenCount removed');
      expect(code.contains('dashActiveMembers'), isFalse, reason: 'dashActiveMembers replaced');
    });
  });
}
