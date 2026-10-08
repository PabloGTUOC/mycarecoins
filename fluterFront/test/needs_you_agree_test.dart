import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/shell.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/utils/needs_you.dart';

class _FakeApi extends ApiClient {
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> requests;
  final List<Map<String, dynamic>> members;

  _FakeApi({
    this.activities = const [],
    this.requests = const [],
    this.members = const [],
  });

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/activities')) {
      return {'activities': activities};
    }
    if (path.startsWith('/api/absences')) return {'absences': []};
    if (path.startsWith('/api/personal-time')) return {'requests': requests};
    if (path.startsWith('/api/dashboard/')) {
      return {'members': members, 'calendar': [], 'objectsOfCare': []};
    }
    if (path.startsWith('/api/marketplace/rewards/')) {
      return {'rewards': [], 'claimed': []};
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
  Future<dynamic> post(String path, [Object? body]) async => {'success': true};
}

AppState _appFor(_FakeApi api, {String role = 'caregiver'}) => AppState(api: api)
  ..families = [
    {'family_id': 1, 'coin_balance': 500, 'role': role}
  ]
  ..profile = {'id': 1, 'display_name': 'Parent'};

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

final _activeMember = {
  'user_id': 1,
  'name': 'Parent',
  'status': 'active',
  'coin_balance': 500
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tour.seen.welcome': true,
      'tour.seen.daily': true,
      'tour.seen.dashboard': true,
      'tour.seen.checklist-dismissed': true,
    });
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  final nothingActionable = _FakeApi(
    members: [_activeMember],
    activities: [
      {
        'id': 1,
        'title': 'My own chore',
        'category': 'care',
        'type': 'household',
        'status': 'pending_validation',
        'assigned_to': 1,
        'is_template': false,
      },
      {
        'id': 2,
        'title': 'Unapproved template',
        'category': 'care',
        'type': 'household',
        'status': 'pending',
        'is_template': true,
      },
    ],
  );

  final twoThings = _FakeApi(
    members: [_activeMember],
    activities: [
      {
        'id': 3,
        'title': 'Dishwasher',
        'category': 'care',
        'type': 'household',
        'status': 'pending_validation',
        'assigned_to': 2,
        'is_template': false,
      },
    ],
    requests: [
      {
        'id': 7,
        'status': 'pending',
        'requester_id': 2,
        'requester_name': 'Sam',
        'requested_of': 1,
        'category': 'self',
        'type': 'rest',
        'title': 'Nap',
        'starts_at': DateTime.now().toIso8601String(),
        'ends_at':
            DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      },
    ],
  );

  group('P2-11: Family and Today agree', () {
    testWidgets('nothing actionable: Family silent, Today all caught up',
        (tester) async {
      phone(tester);
      final app = _appFor(nothingActionable);

      await tester.pumpWidget(_wrap(const Shell(initialIndex: 1), app));
      await tester.pumpAndSettle();
      expect(find.textContaining('needs you'), findsNothing);
      expect(find.text('Go to Today'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_wrap(Shell(key: UniqueKey(), initialIndex: 0), app));
      await tester.pumpAndSettle();
      expect(find.text("You're all caught up."), findsOneWidget);
    });

    testWidgets('Today lists exactly the two things', (tester) async {
      phone(tester);
      final app = _appFor(twoThings);
      await tester.pumpWidget(_wrap(Shell(key: UniqueKey(), initialIndex: 0), app));
      await tester.pumpAndSettle();
      expect(find.text("You're all caught up."), findsNothing);
      expect(find.textContaining('Dishwasher'), findsWidgets);
      expect(find.textContaining('Sam'), findsWidgets);
    });

    testWidgets('validation + cover request: Family says it, Today lists two',
        (tester) async {
      phone(tester);
      final app = _appFor(twoThings);

      await tester.pumpWidget(_wrap(const Shell(initialIndex: 1), app));
      await tester.pumpAndSettle();
      expect(find.textContaining('Something on Today needs you.'),
          findsOneWidget);
      expect(find.text('Go to Today'), findsOneWidget);
      // never a number
      expect(find.textContaining('2 things'), findsNothing);

      final items = needsYouItems(
          app: app,
          activities: twoThings.activities,
          requests: twoThings.requests,
          pendingMembers: const []);
      expect(items.length, 2);
    });
  });

  group('needsYouItems', () {
    AppState caregiver() => _appFor(_FakeApi());
    AppState member() => _appFor(_FakeApi(), role: 'member');

    List<NeedsYouItem> run(AppState app,
            {List<Map<String, dynamic>> a = const [],
            List<Map<String, dynamic>> r = const [],
            List<Map<String, dynamic>> m = const []}) =>
        needsYouItems(
            app: app, activities: a, requests: r, pendingMembers: m);

    final validation = {
      'id': 1,
      'status': 'pending_validation',
      'assigned_to': 2,
      'category': 'care',
      'type': 'care',
    };

    test('validation by someone else for a caregiver', () {
      final out = run(caregiver(), a: [validation]);
      expect(out.single, isA<NeedsValidation>());
    });

    test('validation: own task, member, template excluded', () {
      expect(run(caregiver(), a: [{...validation, 'assigned_to': 1}]), isEmpty);
      expect(run(member(), a: [validation]), isEmpty);
      expect(run(caregiver(), a: [{...validation, 'is_template': true}]),
          isEmpty);
    });

    test('cover request asked of me or anyone; own request excluded', () {
      final req = {
        'status': 'pending',
        'requester_id': 2,
        'requested_of': null,
      };
      expect(run(caregiver(), r: [req]).single, isA<NeedsCoverRequest>());
      expect(run(member(), r: [{...req, 'requested_of': 1}]).single,
          isA<NeedsCoverRequest>());
      expect(run(caregiver(), r: [{...req, 'requested_of': 3}]), isEmpty);
      expect(run(caregiver(), r: [{...req, 'requester_id': 1}]), isEmpty);
      expect(run(caregiver(), r: [{...req, 'status': 'accepted'}]), isEmpty);
    });

    test('pending member approval for caregivers only', () {
      final pm = {'user_id': 5, 'status': 'pending'};
      expect(run(caregiver(), m: [pm]).single, isA<NeedsMemberApproval>());
      expect(run(member(), m: [pm]), isEmpty);
    });

    test('open offers: exclusions for coverage, self, completed, mine, member',
        () {
      final offer = {
        'id': 9,
        'status': 'approved',
        'bounty_amount': 5,
        'assigned_to': 2,
        'category': 'care',
        'type': 'care',
      };
      expect(run(caregiver(), a: [offer]).single, isA<NeedsTakeOverOffer>());
      expect(run(caregiver(), a: [{...offer, 'type': 'coverage'}]), isEmpty);
      expect(run(caregiver(), a: [{...offer, 'category': 'self', 'type': 'rest'}]),
          isEmpty);
      expect(run(caregiver(), a: [{...offer, 'status': 'completed'}]), isEmpty);
      expect(run(caregiver(), a: [{...offer, 'assigned_to': 1}]), isEmpty);
      expect(run(member(), a: [offer]), isEmpty);
      expect(run(caregiver(), a: [{...offer, 'bounty_amount': 0}]), isEmpty);
    });
  });

  test('dashNeedsYou exists in all locales without a number', () {
    for (final code in ['en', 'es', 'fr', 'de']) {
      final l = lookupAppLocalizations(Locale(code));
      expect(l.dashNeedsYou, isNotEmpty);
      expect(RegExp(r'\d').hasMatch(l.dashNeedsYou), isFalse);
    }
  });
}
