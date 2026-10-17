import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_front/api.dart';
import 'package:admin_front/app_state.dart';
import 'package:admin_front/auth.dart';
import 'package:admin_front/screens/family_detail_screen.dart';
import 'package:admin_front/strings.dart';
import 'package:admin_front/theme.dart';
import 'package:provider/provider.dart';
import 'fakes.dart';

void main() {
  late FakeAuthService auth;
  late FakeAdminApi api;
  late AppState state;

  setUp(() {
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

  Widget buildTestWidget({Future<bool> Function(Uri uri)? launchUrlFn}) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildAdminTheme(),
        home: FamilyDetailScreen(
          familyId: 42,
          initialName: 'Wayne Family',
          launchUrlFn: launchUrlFn,
        ),
      ),
    );
  }

  testWidgets(
      'Family detail: grant flow posts right body, revoke asks confirmation then calls DELETE, notify inactive says queued',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/families/42'] = {
      'id': 42,
      'name': 'Wayne Family',
      'createdAt': '2026-01-01T10:00:00.000Z',
      'lastActiveAt': '2026-08-15T12:00:00.000Z',
      'memberCount': 3,
      'pendingMemberCount': 1,
      'actorCount': 1,
      'status': 'dormant',
      'planCode': 'pro',
      'subscriptionStatus': 'active',
    };

    api.responses['GET:/families/42/billing'] = {
      'subscription': {
        'planCode': 'pro',
        'status': 'active',
        'platform': 'ios',
        'provider': 'apple',
        'currentPeriodEnd': '2026-11-01T00:00:00.000Z',
        'billingOwnerUserId': 1001,
      },
      'grants': [
        {
          'id': 7,
          'planCode': 'pro',
          'reason': 'Trial boost',
          'createdAt': '2026-08-01T00:00:00.000Z',
          'expiresAt': '2026-12-31T00:00:00.000Z',
          'revokedAt': null,
          'grantedBy': 1,
        },
      ],
      'recentEvents': [
        {
          'id': 101,
          'provider': 'apple',
          'eventType': 'INITIAL_PURCHASE',
          'processed': true,
          'createdAt': '2026-01-01T10:00:00.000Z',
        },
      ],
    };

    api.responses['GET:/plans'] = {
      'plans': [
        {
          'code': 'pro',
          'name': 'CareCoins Pro',
          'active': true,
          'priceCents': 999,
          'billingPeriod': 'monthly',
        },
        {
          'code': 'supporter',
          'name': 'Supporter',
          'active': true,
          'priceCents': 1999,
          'billingPeriod': 'monthly',
        },
      ],
    };

    api.responses['POST:/families/42/notify-inactive'] = {
      'familyId': 42,
      'status': 'dormant',
    };

    api.responses['DELETE:/families/42/grants/7'] = {
      'success': true,
    };

    api.responses['POST:/families/42/grants'] = {
      'grant': {
        'id': 8,
        'planCode': 'pro',
        'reason': 'Special gift',
        'expiresAt': '2026-11-15T00:00:00.000Z',
        'revokedAt': null,
        'createdAt': '2026-10-15T00:00:00.000Z',
        'grantedBy': 1,
      },
    };

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Verify registry & billing cards rendered
    expect(find.text(Strings.registryCardTitle), findsOneWidget);
    expect(find.text(Strings.billingCardTitle), findsOneWidget);
    expect(find.text(Strings.grantsCardTitle), findsOneWidget);
    expect(find.text(Strings.eventsCardTitle), findsOneWidget);
    expect(find.text('Wayne Family · #42'), findsOneWidget);
    // Verify billing owner row is present with User #1001 (MP2c)
    expect(find.text(Strings.subBillingOwner), findsOneWidget);
    expect(find.text('User #1001'), findsOneWidget);

    // 1. Notify Inactive: tap button -> confirm dialog -> calls POST -> says queued
    final notifyBtn = find.text(Strings.notifyInactiveBtn);
    expect(notifyBtn, findsOneWidget);
    await tester.tap(notifyBtn);
    await tester.pumpAndSettle();

    // Confirm dialog is visible
    expect(find.text(Strings.notifyInactiveConfirmTitle), findsOneWidget);
    expect(find.text(Strings.notifyInactiveConfirmBody), findsOneWidget);

    // Confirm
    await tester.tap(find.text(Strings.confirm));
    await tester.pumpAndSettle();

    // Verify POST called
    expect(
      api.callHistory.any(
        (c) => c.method == 'POST' && c.path == '/families/42/notify-inactive',
      ),
      isTrue,
    );
    expect(find.text(Strings.notifyInactiveQueued), findsOneWidget);

    // 2. Revoke Grant: tap Revoke -> confirm dialog -> calls DELETE
    final revokeBtn = find.text(Strings.revokeGrantBtn);
    expect(revokeBtn, findsOneWidget);
    await tester.ensureVisible(revokeBtn);
    await tester.pumpAndSettle();
    await tester.tap(revokeBtn);
    await tester.pumpAndSettle();

    // Confirm dialog is visible
    expect(find.text(Strings.revokeGrantConfirmTitle), findsOneWidget);
    await tester.tap(find.text(Strings.confirm));
    await tester.pumpAndSettle();

    // Verify DELETE called
    expect(
      api.callHistory.any(
        (c) => c.method == 'DELETE' && c.path == '/families/42/grants/7',
      ),
      isTrue,
    );
    expect(find.text(Strings.revokeGrantSuccess), findsOneWidget);

    // 3. Grant Plan flow: tap Grant Plan -> fill fields -> confirm -> calls POST with right body
    final grantPlanBtn = find.text(Strings.grantPlanBtn);
    expect(grantPlanBtn, findsOneWidget);
    await tester.ensureVisible(grantPlanBtn);
    await tester.pumpAndSettle();
    await tester.tap(grantPlanBtn);
    await tester.pumpAndSettle();

    expect(find.text(Strings.grantPlanDialogTitle), findsOneWidget);

    // Enter reason & days
    final textFields = find.byType(TextField);
    // Reason is the first TextField, days is the second
    await tester.enterText(textFields.at(0), 'Special gift');
    await tester.enterText(textFields.at(1), '30');

    await tester.tap(find.text(Strings.confirm));
    await tester.pumpAndSettle();

    final grantCall = api.callHistory.lastWhere(
      (c) => c.method == 'POST' && c.path == '/families/42/grants',
    );
    expect(grantCall.body, isA<Map<String, dynamic>>());
    final body = grantCall.body as Map<String, dynamic>;
    expect(body['planCode'], 'pro');
    expect(body['reason'], 'Special gift');
    expect(body['expiresAt'], isNotNull);
    expect(find.text(Strings.grantSuccess), findsOneWidget);
  });

  testWidgets(
      'Grants table headers and three statuses: Active, Expired, Revoked',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/families/42'] = {
      'id': 42,
      'name': 'Wayne Family',
      'createdAt': '2026-01-01T10:00:00.000Z',
      'lastActiveAt': '2026-08-15T12:00:00.000Z',
      'memberCount': 3,
      'pendingMemberCount': 1,
      'actorCount': 1,
      'status': 'active',
      'planCode': 'pro',
      'subscriptionStatus': 'active',
    };

    api.responses['GET:/families/42/billing'] = {
      'subscription': null,
      'grants': [
        {
          'id': 1,
          'planCode': 'supporter',
          'reason': 'Active grant',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'expiresAt': '2099-01-01T00:00:00.000Z',
          'revokedAt': null,
        },
        {
          'id': 2,
          'planCode': 'pro',
          'reason': 'Expired grant',
          'createdAt': '2020-01-01T00:00:00.000Z',
          'expiresAt': '2020-02-01T00:00:00.000Z',
          'revokedAt': null,
        },
        {
          'id': 3,
          'planCode': 'pro',
          'reason': 'Revoked grant',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'expiresAt': '2099-01-01T00:00:00.000Z',
          'revokedAt': '2026-02-01T00:00:00.000Z',
        },
      ],
      'recentEvents': [],
    };

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Verify headers
    expect(find.text(Strings.colPlan), findsWidgets);
    expect(find.text(Strings.colReason), findsOneWidget);
    expect(find.text(Strings.colGranted), findsOneWidget);
    expect(find.text(Strings.colExpires), findsOneWidget);
    expect(find.text(Strings.colStatus), findsWidgets);

    // Verify three statuses render
    expect(find.text(Strings.grantStatusActive), findsOneWidget);
    expect(find.text(Strings.grantStatusExpired), findsOneWidget);
    expect(find.text(Strings.grantStatusRevoked), findsOneWidget);

    // Revoke button should only be available for non-revoked grants (2 out of 3)
    expect(find.text(Strings.revokeGrantBtn), findsNWidgets(2));
  });

  testWidgets('Family detail: billing owner displays dash when null', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/families/42'] = {
      'id': 42,
      'name': 'Wayne Family',
      'createdAt': '2026-01-01T10:00:00.000Z',
      'lastActiveAt': '2026-08-15T12:00:00.000Z',
      'memberCount': 3,
      'pendingMemberCount': 1,
      'actorCount': 1,
      'status': 'dormant',
      'planCode': 'pro',
      'subscriptionStatus': 'active',
    };

    api.responses['GET:/families/42/billing'] = {
      'subscription': {
        'planCode': 'pro',
        'status': 'active',
        'platform': 'ios',
        'provider': 'apple',
        'currentPeriodEnd': '2026-11-01T00:00:00.000Z',
        'billingOwnerUserId': null,
      },
      'grants': [],
      'recentEvents': [],
    };

    api.responses['GET:/plans'] = {'plans': []};

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text(Strings.subBillingOwner), findsOneWidget);
    expect(find.text(Strings.emptyDash), findsWidgets);
  });

  testWidgets(
      'Family detail: RevenueCat column shows Synced, Pending, Failed with tooltip, and Retry button calls POST rc-sync',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/families/42'] = {
      'id': 42,
      'name': 'Wayne Family',
      'createdAt': '2026-01-01T10:00:00.000Z',
      'lastActiveAt': '2026-08-15T12:00:00.000Z',
      'memberCount': 3,
      'pendingMemberCount': 0,
      'actorCount': 0,
      'status': 'active',
      'planCode': 'pro',
      'subscriptionStatus': 'active',
    };

    api.responses['GET:/families/42/billing'] = {
      'subscription': null,
      'grants': [
        {
          'id': 1,
          'planCode': 'pro',
          'reason': 'Synced grant',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'expiresAt': '2099-01-01T00:00:00.000Z',
          'revokedAt': null,
          'rcSync': {
            'status': 'synced',
            'attempts': 0,
            'lastError': null,
            'syncedAt': '2026-01-01T00:05:00.000Z',
          },
        },
        {
          'id': 2,
          'planCode': 'pro',
          'reason': 'Pending grant',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'expiresAt': '2099-01-01T00:00:00.000Z',
          'revokedAt': null,
          'rcSync': {
            'status': 'pending',
            'attempts': 1,
            'lastError': null,
            'syncedAt': null,
          },
        },
        {
          'id': 3,
          'planCode': 'pro',
          'reason': 'Failed grant',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'expiresAt': '2099-01-01T00:00:00.000Z',
          'revokedAt': null,
          'rcSync': {
            'status': 'failed',
            'attempts': 3,
            'lastError': 'Customer does not exist in RevenueCat',
            'syncedAt': null,
          },
        },
      ],
      'recentEvents': [],
    };

    api.responses['POST:/families/42/grants/3/rc-sync'] = {
      'status': 'synced',
    };

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Verify column header
    final dataTable = find.byType(DataTable);
    expect(
        find.descendant(of: dataTable, matching: find.text(Strings.colRevenueCat)),
        findsOneWidget);
    expect(
        find.descendant(of: dataTable, matching: find.text(Strings.rcSyncSynced)),
        findsOneWidget);
    expect(
        find.descendant(of: dataTable, matching: find.text(Strings.rcSyncPending)),
        findsOneWidget);
    expect(
        find.descendant(of: dataTable, matching: find.text(Strings.rcSyncFailed)),
        findsOneWidget);

    // Verify tooltip on failed row
    final tooltip = tester.widget<Tooltip>(
        find.descendant(of: dataTable, matching: find.byType(Tooltip)));
    expect(tooltip.message, 'Customer does not exist in RevenueCat');

    // Retry button should only appear for pending and failed (2 out of 3)
    final retryBtns = find.text(Strings.rcSyncRetryBtn);
    expect(retryBtns, findsNWidgets(2));

    // Tap retry on the failed grant (the second retry button)
    await tester.ensureVisible(retryBtns.last);
    await tester.pumpAndSettle();
    await tester.tap(retryBtns.last);
    await tester.pumpAndSettle();

    // Verify POST was sent to the right path
    final postCall = api.callHistory.firstWhere(
      (c) => c.method == 'POST' && c.path == '/families/42/grants/3/rc-sync',
    );
    expect(postCall, isNotNull);
  });

  testWidgets(
      'Family detail RevenueCat card: renders populated data with customers, entitlements, and links out to dashboard',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/families/42'] = {
      'id': 42,
      'name': 'Wayne Family',
      'createdAt': '2026-01-01T10:00:00.000Z',
      'lastActiveAt': '2026-08-15T12:00:00.000Z',
      'status': 'active',
    };
    api.responses['GET:/families/42/billing'] = {
      'subscription': null,
      'grants': [],
      'recentEvents': [],
    };
    api.responses['GET:/families/42/revenuecat'] = {
      'familyCustomer': {
        'customerId': 'family_42',
        'found': true,
        'entitlements': [
          {
            'id': 'carecoins_free',
            'expiresAt': '2026-12-31T00:00:00.000Z',
            'store': 'promotional',
            'grantType': 'free',
          },
        ],
        'lastSeenAt': '2026-10-15T10:00:00.000Z',
      },
      'billingOwnerCustomer': {
        'customerId': '1001',
        'found': true,
        'entitlements': [
          {
            'id': 'carecoins_pro',
            'expiresAt': '2026-11-15T00:00:00.000Z',
            'store': 'app_store',
          },
        ],
        'lastSeenAt': '2026-10-16T08:00:00.000Z',
      },
      'mismatches': [],
    };

    final launchedUris = <Uri>[];
    await tester.pumpWidget(buildTestWidget(
      launchUrlFn: (uri) async {
        launchedUris.add(uri);
        return true;
      },
    ));
    await tester.pumpAndSettle();

    // Verify card title
    expect(find.text(Strings.rcCardTitle), findsOneWidget);

    // Verify family customer
    expect(find.text(Strings.rcFamilyCustomerTitle), findsOneWidget);
    expect(find.text('family_42'), findsOneWidget);
    expect(find.text(Strings.rcStatusFound), findsNWidgets(2)); // both customers found

    // Verify entitlements
    expect(
      find.text(Strings.rcEntitlementSummary(
        id: 'carecoins_free',
        expiresAt: '2026-12-31T00:00:00.000Z',
        store: 'promotional',
        grantType: 'free',
      )),
      findsOneWidget,
    );

    // Verify billing owner customer
    expect(find.text(Strings.rcBillingOwnerCustomerTitle), findsOneWidget);
    expect(find.text('1001'), findsOneWidget);

    // Tap link out to RevenueCat dashboard for family customer
    final openBtns = find.text(Strings.rcOpenInDashboard);
    expect(openBtns, findsNWidgets(2));
    await tester.tap(openBtns.first);
    await tester.pumpAndSettle();

    expect(launchedUris, hasLength(1));
    expect(
      launchedUris.first.toString(),
      Strings.rcCustomerDashboardUrl('family_42'),
    );
  });

  testWidgets(
      'Family detail RevenueCat card: renders not-configured state on 503',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/families/42'] = {
      'id': 42,
      'name': 'Wayne Family',
      'status': 'active',
    };
    api.responses['GET:/families/42/billing'] = {
      'subscription': null,
      'grants': [],
      'recentEvents': [],
    };
    api.responses['GET:/families/42/revenuecat'] = AdminApiException(
      statusCode: 503,
      code: 'revenueCatNotConfigured',
      message: 'RevenueCat is not configured.',
    );

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text(Strings.errRevenueCatNotConfigured), findsOneWidget);
  });

  testWidgets(
      'Family detail RevenueCat card: renders unavailable error and allows retry with refresh=1',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/families/42'] = {
      'id': 42,
      'name': 'Wayne Family',
      'status': 'active',
    };
    api.responses['GET:/families/42/billing'] = {
      'subscription': null,
      'grants': [],
      'recentEvents': [],
    };
    api.responses['GET:/families/42/revenuecat'] = AdminApiException(
      statusCode: 502,
      code: 'revenueCatUnavailable',
      message: 'RevenueCat unavailable',
    );

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text(Strings.errRevenueCatUnavailable), findsOneWidget);

    // Provide successful response for refresh
    api.responses['GET:/families/42/revenuecat?refresh=1'] = {
      'familyCustomer': {
        'customerId': 'family_42',
        'found': true,
        'entitlements': [],
        'lastSeenAt': null,
      },
      'billingOwnerCustomer': null,
      'mismatches': [],
    };

    // Tap retry button next to error
    await tester.tap(find.text(Strings.retry));
    await tester.pumpAndSettle();

    expect(find.text(Strings.errRevenueCatUnavailable), findsNothing);
    expect(find.text('family_42'), findsOneWidget);
  });

  testWidgets(
      'Family detail RevenueCat card: renders mismatch warning rows with theme warning styling',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/families/42'] = {
      'id': 42,
      'name': 'Wayne Family',
      'status': 'active',
    };
    api.responses['GET:/families/42/billing'] = {
      'subscription': null,
      'grants': [],
      'recentEvents': [],
    };
    api.responses['GET:/families/42/revenuecat'] = {
      'familyCustomer': {
        'customerId': 'family_42',
        'found': false,
        'entitlements': [],
        'lastSeenAt': null,
      },
      'billingOwnerCustomer': null,
      'mismatches': [
        {
          'code': 'freePlanNotMirrored',
          'message': 'The family has an active grant synced in our database, but no active entitlement exists in RevenueCat.',
        },
      ],
    };

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text(Strings.rcMismatchTitle('freePlanNotMirrored')), findsOneWidget);
    expect(
      find.text('The family has an active grant synced in our database, but no active entitlement exists in RevenueCat.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets(
      'Family detail RevenueCat card: handles customer not found and no billing owner',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/families/42'] = {
      'id': 42,
      'name': 'Wayne Family',
      'status': 'active',
    };
    api.responses['GET:/families/42/billing'] = {
      'subscription': null,
      'grants': [],
      'recentEvents': [],
    };
    api.responses['GET:/families/42/revenuecat'] = {
      'familyCustomer': {
        'customerId': 'family_42',
        'found': false,
        'entitlements': [],
        'lastSeenAt': null,
      },
      'billingOwnerCustomer': null,
      'mismatches': [],
    };

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text(Strings.rcStatusNotFound), findsOneWidget);
    expect(find.text(Strings.rcNoBillingOwner), findsOneWidget);
  });
}
