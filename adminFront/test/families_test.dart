import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_front/auth.dart';
import 'package:admin_front/main.dart';
import 'package:admin_front/strings.dart';
import 'fakes.dart';

void main() {
  late FakeAuthService auth;
  late FakeAdminApi api;

  setUp(() {
    auth = FakeAuthService(
      initialUser: const OperatorUser(
        uid: 'op_1',
        email: 'operator@carecoins.app',
      ),
    );
    api = FakeAdminApi();
    api.responses['GET:/status'] = {'ok': true, 'adminId': 1};
  });

  tearDown(() {
    auth.dispose();
  });

  testWidgets(
      'Families: rows render from a fake response, search & filter send right query params, next page requests page=2',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/families'] = {
      'families': [
        {
          'id': 42,
          'name': 'Wayne Family',
          'status': 'active',
          'planCode': 'pro',
          'subscriptionStatus': 'active',
          'memberCount': 4,
          'pendingMemberCount': 1,
          'actorCount': 2,
          'createdAt': '2026-01-01T10:00:00.000Z',
          'lastActiveAt': '2026-10-15T12:00:00.000Z',
        },
        {
          'id': 99,
          'name': 'Kent Family',
          'status': 'dormant',
          'planCode': 'free',
          'subscriptionStatus': 'trialing',
          'memberCount': 2,
          'pendingMemberCount': 0,
          'actorCount': 1,
          'createdAt': '2026-02-01T10:00:00.000Z',
          'lastActiveAt': '2026-08-15T12:00:00.000Z',
        },
      ],
      'total': 45,
      'page': 1,
      'pageSize': 20,
    };

    await tester.pumpWidget(AdminApp(authService: auth, api: api));
    await tester.pumpAndSettle();

    // 1. Verify rows render
    expect(find.text('Wayne Family'), findsOneWidget);
    expect(find.text('#42'), findsOneWidget);
    expect(find.text(Strings.statusActive), findsWidgets); // badge + filter
    expect(find.text('Kent Family'), findsOneWidget);
    expect(find.text('#99'), findsOneWidget);
    expect(find.text(Strings.statusDormant), findsWidgets);

    // Verify pagination info: total 45 with pageSize 20 -> 3 pages
    expect(find.text(Strings.pageInfo(1, 3, 45)), findsOneWidget);

    // 2. Search box test (debounced 300 ms)
    final searchInput = find.byType(TextField);
    await tester.enterText(searchInput, 'Wayne');
    await tester.pump(const Duration(milliseconds: 100)); // Still debouncing
    // Debounce expires
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    final searchCall = api.callHistory.lastWhere(
      (c) => c.method == 'GET' && c.path.contains('/families'),
    );
    expect(searchCall.path, contains('search=Wayne'));
    expect(searchCall.path, contains('page=1'));

    // 3. Heartbeat filter test (SegmentedButton)
    await tester.tap(find.text(Strings.statusDormant).first);
    await tester.pumpAndSettle();

    final filterCall = api.callHistory.lastWhere(
      (c) => c.method == 'GET' && c.path.contains('/families'),
    );
    expect(filterCall.path, contains('status=dormant'));
    expect(filterCall.path, contains('page=1'));

    // 4. Next page button
    api.responses['GET:/families'] = {
      'families': [
        {
          'id': 101,
          'name': 'Stark Family',
          'status': 'active',
          'planCode': 'pro',
          'subscriptionStatus': 'active',
          'memberCount': 3,
          'pendingMemberCount': 0,
          'actorCount': 1,
          'createdAt': '2026-03-01T10:00:00.000Z',
          'lastActiveAt': '2026-10-15T12:00:00.000Z',
        },
      ],
      'total': 45,
      'page': 2,
      'pageSize': 20,
    };

    final nextBtn = find.text(Strings.nextPage);
    expect(nextBtn, findsOneWidget);
    await tester.tap(nextBtn);
    await tester.pumpAndSettle();

    // Verify Pending and Actors columns are present (MP2c)
    expect(find.text(Strings.colPending), findsOneWidget);
    expect(find.text(Strings.colActors), findsOneWidget);

    final page2Call = api.callHistory.lastWhere(
      (c) => c.method == 'GET' && c.path.contains('/families'),
    );
    expect(page2Call.path, contains('page=2'));
    expect(find.text('Stark Family'), findsOneWidget);
  });

  testWidgets(
      'Families table displays all columns including Pending and Actors at 1440 px',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/families'] = {
      'families': [
        {
          'id': 1,
          'name': 'Test Family',
          'status': 'active',
          'planCode': 'free',
          'subscriptionStatus': 'none',
          'memberCount': 5,
          'pendingMemberCount': 2,
          'actorCount': 3,
          'createdAt': '2026-01-01T10:00:00.000Z',
          'lastActiveAt': '2026-01-01T10:00:00.000Z',
        },
      ],
      'total': 1,
      'page': 1,
      'pageSize': 20,
    };

    await tester.pumpWidget(AdminApp(authService: auth, api: api));
    await tester.pumpAndSettle();

    expect(find.text(Strings.colName), findsOneWidget);
    expect(find.text(Strings.colId), findsOneWidget);
    expect(find.text(Strings.colHeartbeat), findsOneWidget);
    expect(find.text(Strings.colPlan), findsOneWidget);
    expect(find.text(Strings.colSubscription), findsOneWidget);
    expect(find.text(Strings.colMembers), findsOneWidget);
    expect(find.text(Strings.colPending), findsOneWidget);
    expect(find.text(Strings.colActors), findsOneWidget);
    expect(find.text(Strings.colCreated), findsOneWidget);
    expect(find.text(Strings.colLastActive), findsOneWidget);
    expect(find.text(Strings.colActions), findsOneWidget);
    // Verify count values in cells
    expect(find.text('5'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets(
      'Pagination info uses singular for 1 family and plural for multiple',
      (tester) async {
    expect(Strings.pageInfo(1, 1, 1), 'Page 1 of 1 (1 family)');
    expect(Strings.pageInfo(1, 1, 0), 'Page 1 of 1 (0 families)');
    expect(Strings.pageInfo(1, 2, 3), 'Page 1 of 2 (3 families)');
  });

  testWidgets(
      'Families table displays Scrollbar and renders properly on narrow screens',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/families'] = {
      'families': [
        {
          'id': 1,
          'name': 'Test Family',
          'status': 'active',
          'planCode': 'free',
          'subscriptionStatus': 'none',
          'memberCount': 2,
          'createdAt': '2026-01-01T10:00:00.000Z',
          'lastActiveAt': '2026-01-01T10:00:00.000Z',
        },
      ],
      'total': 1,
      'page': 1,
      'pageSize': 20,
    };

    await tester.pumpWidget(AdminApp(authService: auth, api: api));
    await tester.pumpAndSettle();

    expect(find.byType(Scrollbar), findsWidgets);
    expect(find.text(Strings.colName), findsOneWidget);
    expect(find.text('Page 1 of 1 (1 family)'), findsOneWidget);
  });
}
