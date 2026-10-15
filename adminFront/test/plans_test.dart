import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_front/app_state.dart';
import 'package:admin_front/auth.dart';
import 'package:admin_front/screens/plans_screen.dart';
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

  Widget buildTestWidget() {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildAdminTheme(),
        home: const PlansScreen(),
      ),
    );
  }

  testWidgets(
      'Plans: create posts, edit patches, code is read-only when editing',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/plans'] = {
      'plans': [
        {
          'code': 'pro',
          'name': 'Pro Plan',
          'priceCents': 999,
          'currency': 'EUR',
          'billingPeriod': 'monthly',
          'limits': {'max_members': 10},
          'isDefault': true,
          'active': true,
        },
      ],
    };

    api.responses['POST:/plans'] = {
      'plan': {
        'code': 'enterprise',
        'name': 'Enterprise Plan',
        'priceCents': 4999,
        'currency': 'EUR',
        'billingPeriod': 'monthly',
        'limits': {},
        'isDefault': false,
        'active': true,
      },
    };

    api.responses['PATCH:/plans/pro'] = {
      'plan': {
        'code': 'pro',
        'name': 'Pro Plan Updated',
        'priceCents': 1299,
        'currency': 'EUR',
        'billingPeriod': 'monthly',
        'limits': {},
        'isDefault': true,
        'active': true,
      },
    };

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Verify initial row
    expect(find.text('pro'), findsOneWidget);
    expect(find.text('Pro Plan'), findsOneWidget);

    // 1. Create plan
    final newPlanBtn = find.text(Strings.newPlanBtn);
    expect(newPlanBtn, findsOneWidget);
    await tester.tap(newPlanBtn);
    await tester.pumpAndSettle();

    expect(find.text(Strings.newPlanDialogTitle), findsOneWidget);

    // Enter code, name, price
    final codeField = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.labelText == Strings.planCodeLabel &&
          w.enabled == true,
    );
    expect(codeField, findsOneWidget);
    await tester.enterText(codeField, 'enterprise');

    final nameField = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.labelText == Strings.planNameLabel,
    );
    await tester.enterText(nameField, 'Enterprise Plan');

    final priceField = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.labelText == Strings.planPriceLabel,
    );
    await tester.enterText(priceField, '4999');

    await tester.tap(find.text(Strings.save));
    await tester.pumpAndSettle();

    // Verify POST called
    final postCall = api.callHistory.lastWhere(
      (c) => c.method == 'POST' && c.path == '/plans',
    );
    final postBody = postCall.body as Map<String, dynamic>;
    expect(postBody['code'], 'enterprise');
    expect(postBody['name'], 'Enterprise Plan');
    expect(postBody['priceCents'], 4999);
    expect(find.text(Strings.planSaveSuccess), findsOneWidget);

    // 2. Edit plan
    final editBtn = find.text(Strings.editPlanBtn);
    expect(editBtn, findsOneWidget);
    await tester.tap(editBtn);
    await tester.pumpAndSettle();

    expect(find.text(Strings.editPlanDialogTitle), findsOneWidget);

    // Check code field is disabled / read-only
    final disabledCodeField = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.labelText == Strings.planCodeLabel &&
          w.enabled == false &&
          w.controller?.text == 'pro',
    );
    expect(disabledCodeField, findsOneWidget);

    // Update name
    final editNameField = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.labelText == Strings.planNameLabel,
    );
    await tester.enterText(editNameField, 'Pro Plan Updated');

    await tester.tap(find.text(Strings.save));
    await tester.pumpAndSettle();

    // Verify PATCH called to /plans/pro
    final patchCall = api.callHistory.lastWhere(
      (c) => c.method == 'PATCH' && c.path == '/plans/pro',
    );
    final patchBody = patchCall.body as Map<String, dynamic>;
    expect(patchBody['name'], 'Pro Plan Updated');
    expect(find.text(Strings.planSaveSuccess), findsOneWidget);
  });
}
