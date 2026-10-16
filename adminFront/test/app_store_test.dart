import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_front/api.dart';
import 'package:admin_front/app_state.dart';
import 'package:admin_front/auth.dart';
import 'package:admin_front/screens/app_store_screen.dart';
import 'package:admin_front/screens/shell.dart';
import 'package:admin_front/strings.dart';
import 'package:admin_front/theme.dart';
import 'package:provider/provider.dart';
import 'fakes.dart';

void main() {
  late FakeAuthService auth;
  late FakeAdminApi api;
  late AppState state;
  final launchedUrls = <Uri>[];

  setUp(() {
    launchedUrls.clear();
    auth = FakeAuthService(
      initialUser: const OperatorUser(
        uid: 'op_1',
        email: 'operator@carecoins.app',
      ),
    );
    api = FakeAdminApi();
    state = AppState(api: api, auth: auth);
  });

  tearDown(() {
    auth.dispose();
  });

  Widget buildTestWidget({Future<bool> Function(Uri)? launchUrlFn}) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildAdminTheme(),
        home: AppStoreScreen(
          launchUrlFn: launchUrlFn ??
              (u) async {
                launchedUrls.add(u);
                return true;
              },
        ),
      ),
    );
  }

  testWidgets(
      'App Store: not-configured state renders 503 card and nothing else',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/appstore/catalog'] = AdminApiException(
      statusCode: 503,
      code: 'appStoreNotConfigured',
      message: 'App Store keys are not configured.',
    );

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text(Strings.appStoreNotConfiguredTitle), findsOneWidget);
    expect(find.text(Strings.appStoreNotConfiguredBody), findsOneWidget);

    // Ensure nothing else from the configured screen is rendered
    expect(find.text(Strings.catalogTitle), findsNothing);
    expect(find.text(Strings.lookupTitle), findsNothing);
    expect(find.text(Strings.linkAppStoreConnect), findsNothing);
    expect(find.text(Strings.linkRevenueCat), findsNothing);
  });

  testWidgets(
      'App Store: catalog renders subscription groups, subscriptions, and prices',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/appstore/catalog'] = {
      'app': {
        'id': 'app_1',
        'name': 'CareCoins App',
        'bundleId': 'com.carecoins.app',
      },
      'subscriptionGroups': [
        {
          'id': 'group_1',
          'referenceName': 'CareCoins Subscriptions',
          'subscriptions': [
            {
              'id': 'sub_1',
              'name': 'CareCoins Monthly',
              'productId': 'cc_monthly_tier1',
              'state': 'APPROVED',
              'prices': [
                {
                  'territory': 'USA',
                  'customerPrice': '4.99',
                  'currency': 'USD',
                  'startDate': '2024-01-01',
                },
              ],
            },
          ],
        },
      ],
    };

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text(Strings.appStoreTitle), findsOneWidget);
    expect(find.text(Strings.catalogTitle), findsOneWidget);
    expect(find.text('CareCoins Subscriptions'), findsOneWidget);
    expect(find.text('CareCoins Monthly'), findsOneWidget);
    expect(find.text('cc_monthly_tier1'), findsOneWidget);
    expect(find.text('APPROVED'), findsOneWidget);
    expect(find.text('4.99 USD (USA)'), findsOneWidget);

    expect(find.text(Strings.linkAppStoreConnect), findsOneWidget);
    expect(find.text(Strings.linkRevenueCat), findsOneWidget);
  });

  testWidgets('App Store: refresh button calls /appstore/catalog?refresh=1',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/appstore/catalog'] = {
      'app': {'id': 'app_1'},
      'subscriptionGroups': [],
    };
    api.responses['GET:/appstore/catalog?refresh=1'] = {
      'app': {'id': 'app_1'},
      'subscriptionGroups': [],
    };

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    final refreshBtn = find.text(Strings.refreshCatalogBtn);
    expect(refreshBtn, findsOneWidget);

    await tester.tap(refreshBtn);
    await tester.pumpAndSettle();

    expect(
      api.callHistory.any(
        (c) => c.method == 'GET' && c.path == '/appstore/catalog?refresh=1',
      ),
      isTrue,
    );
  });

  testWidgets(
      'App Store: transaction lookup calls /appstore/transactions/:id with environment and renders result',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/appstore/catalog'] = {
      'app': {'id': 'app_1'},
      'subscriptionGroups': [],
    };
    api.responses['GET:/appstore/transactions/2000000123456789?environment=production'] = {
      'productId': 'cc_monthly_tier1',
      'transactionId': '2000000123456789',
      'originalTransactionId': '1000000123456789',
      'purchaseDate': '2024-03-01T12:00:00.000Z',
      'expiresDate': '2024-04-01T12:00:00.000Z',
      'environment': 'Production',
      'type': 'Auto-Renewable Subscription',
      'inAppOwnershipType': 'PURCHASED',
      'revocationDate': null,
      'revocationReason': null,
      'autoRenewStatus': 1,
      'autoRenewProductId': 'cc_monthly_tier1',
      'expirationIntent': null,
      'status': 1,
    };
    api.responses['GET:/appstore/transactions/2000000123456789?environment=sandbox'] = {
      'productId': 'cc_monthly_tier1',
      'transactionId': '2000000123456789',
      'originalTransactionId': '1000000123456789',
      'purchaseDate': '2024-03-01T12:00:00.000Z',
      'expiresDate': '2024-04-01T12:00:00.000Z',
      'environment': 'Sandbox',
      'type': 'Auto-Renewable Subscription',
      'inAppOwnershipType': 'PURCHASED',
      'revocationDate': null,
      'revocationReason': null,
      'autoRenewStatus': 1,
      'autoRenewProductId': 'cc_monthly_tier1',
      'expirationIntent': null,
      'status': 1,
    };

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    final inputFinder = find.byType(TextField);
    expect(inputFinder, findsOneWidget);

    await tester.enterText(inputFinder, '2000000123456789');
    await tester.pump();

    final lookupBtn = find.text(Strings.lookupBtn);
    expect(lookupBtn, findsOneWidget);

    // Production lookup
    await tester.tap(lookupBtn);
    await tester.pumpAndSettle();

    expect(
      api.callHistory.any(
        (c) =>
            c.method == 'GET' &&
            c.path ==
                '/appstore/transactions/2000000123456789?environment=production',
      ),
      isTrue,
    );

    expect(find.text('2000000123456789'), findsNWidgets(2));
    expect(find.text('1000000123456789'), findsOneWidget);
    expect(find.text('Production'), findsNWidgets(2));
    expect(find.text('PURCHASED'), findsOneWidget);
    expect(find.text(Strings.autoRenewOn), findsOneWidget);

    // Switch to Sandbox
    final sandboxSegment = find.text(Strings.envSandbox);
    await tester.tap(sandboxSegment);
    await tester.pumpAndSettle();

    await tester.tap(lookupBtn);
    await tester.pumpAndSettle();

    expect(
      api.callHistory.any(
        (c) =>
            c.method == 'GET' &&
            c.path ==
                '/appstore/transactions/2000000123456789?environment=sandbox',
      ),
      isTrue,
    );
    expect(find.text('Sandbox'), findsNWidgets(2));
  });

  testWidgets('App Store: transaction lookup handles 404 not found message',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/appstore/catalog'] = {
      'app': {'id': 'app_1'},
      'subscriptionGroups': [],
    };
    api.responses['GET:/appstore/transactions/99999?environment=production'] =
        AdminApiException(
      statusCode: 404,
      code: 'notFound',
      message: 'Transaction not found.',
    );

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '99999');
    await tester.pump();

    await tester.tap(find.text(Strings.lookupBtn));
    await tester.pumpAndSettle();

    expect(find.text(Strings.txNotFound), findsOneWidget);
  });

  testWidgets('App Store: external links invoke launchUrl', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/appstore/catalog'] = {
      'app': {'id': 'app_1'},
      'subscriptionGroups': [],
    };

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    final ascBtn = find.text(Strings.linkAppStoreConnect);
    expect(ascBtn, findsOneWidget);
    await tester.tap(ascBtn);
    await tester.pumpAndSettle();

    expect(launchedUrls.contains(Uri.parse(Strings.appStoreConnectUrl)), isTrue);

    final rcBtn = find.text(Strings.linkRevenueCat);
    expect(rcBtn, findsOneWidget);
    await tester.tap(rcBtn);
    await tester.pumpAndSettle();

    expect(
      launchedUrls.contains(Uri.parse(Strings.revenueCatCustomersUrl)),
      isTrue,
    );
  });

  testWidgets(
      'App Store: Shell navigation destination switches to AppStoreScreen',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/status'] = {'ok': true, 'adminId': 1};
    api.responses['GET:/families'] = {
      'families': [],
      'total': 0,
      'page': 1,
      'pageSize': 20,
    };
    api.responses['GET:/appstore/catalog'] = {
      'app': {'id': 'app_1'},
      'subscriptionGroups': [],
    };

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: buildAdminTheme(),
          home: const Shell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final navDestination = find.text(Strings.navAppStore);
    expect(navDestination, findsOneWidget);

    await tester.tap(navDestination);
    await tester.pumpAndSettle();

    expect(find.byType(AppStoreScreen), findsOneWidget);
  });
}
