import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_front/api.dart';
import 'package:admin_front/auth.dart';
import 'package:admin_front/main.dart';
import 'package:admin_front/strings.dart';
import 'fakes.dart';

void main() {
  late FakeAuthService auth;
  late FakeAdminApi api;

  setUp(() {
    auth = FakeAuthService();
    api = FakeAdminApi();
  });

  tearDown(() {
    auth.dispose();
  });

  testWidgets('/status 403 adminOnly shows the not-an-operator screen',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/status'] = AdminApiException(
      statusCode: 403,
      code: 'adminOnly',
      message: 'Requires platform admin.',
    );

    auth.setUser(const OperatorUser(
      uid: 'user_123',
      email: 'non_operator@example.com',
    ));

    await tester.pumpWidget(AdminApp(authService: auth, api: api));
    await tester.pumpAndSettle();

    expect(find.text(Strings.notAnOperatorTitle), findsOneWidget);
    expect(find.text(Strings.notAnOperatorMessage), findsOneWidget);
    expect(find.text('non_operator@example.com'), findsOneWidget);
    expect(find.text(Strings.signOut), findsOneWidget);

    // Clicking Sign out returns to sign-in screen
    await tester.tap(find.text(Strings.signOut));
    await tester.pumpAndSettle();

    expect(find.text(Strings.signInTitle), findsOneWidget);
  });

  testWidgets('/status 200 ok shows console layout', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/status'] = {'ok': true, 'adminId': 1};
    api.responses['GET:/families'] = {
      'families': [],
      'total': 0,
      'page': 1,
      'pageSize': 20,
    };

    auth.setUser(const OperatorUser(
      uid: 'admin_123',
      email: 'admin@carecoins.app',
    ));

    await tester.pumpWidget(AdminApp(authService: auth, api: api));
    await tester.pumpAndSettle();

    expect(find.text(Strings.appTitle), findsOneWidget);
    expect(find.text(Strings.navFamilies), findsWidgets);
    expect(find.text(Strings.navPlans), findsOneWidget);
    expect(find.text(Strings.navAppStore), findsOneWidget);
    expect(find.text('admin@carecoins.app'), findsOneWidget);
  });

  testWidgets('/status error shows retry button and retries successfully',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.queueResponse(
      'GET',
      '/status',
      AdminApiException(statusCode: 500, message: 'Server down'),
    );
    api.queueResponse('GET', '/status', {'ok': true, 'adminId': 1});
    api.responses['GET:/families'] = {
      'families': [],
      'total': 0,
      'page': 1,
      'pageSize': 20,
    };

    auth.setUser(const OperatorUser(
      uid: 'admin_123',
      email: 'admin@carecoins.app',
    ));

    await tester.pumpWidget(AdminApp(authService: auth, api: api));
    await tester.pumpAndSettle();

    expect(find.text(Strings.retry), findsOneWidget);

    // Tap retry
    await tester.tap(find.text(Strings.retry));
    await tester.pumpAndSettle();

    expect(find.text(Strings.appTitle), findsOneWidget);
  });

  testWidgets(
      '/status 403 accessMissing shows error state with retry and mapped message, not not-an-operator',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.responses['GET:/status'] = AdminApiException(
      statusCode: 403,
      code: 'accessMissing',
      message: 'Cloudflare Access token missing',
    );

    auth.setUser(const OperatorUser(
      uid: 'user_123',
      email: 'operator@carecoins.app',
    ));

    await tester.pumpWidget(AdminApp(authService: auth, api: api));
    await tester.pumpAndSettle();

    // Must NOT show notAnOperator screen
    expect(find.text(Strings.notAnOperatorTitle), findsNothing);
    // Must show mapped error and retry
    expect(find.text(Strings.errAccessMissing), findsOneWidget);
    expect(find.text(Strings.retry), findsOneWidget);
  });

  testWidgets(
      'sign-in with wrong-password shows mapped error banner',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    auth.signInErrorCode = 'wrong-password';

    await tester.pumpWidget(AdminApp(authService: auth, api: api));
    await tester.pumpAndSettle();

    expect(find.text(Strings.signInTitle), findsOneWidget);

    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'op@carecoins.app');
    await tester.enterText(textFields.at(1), 'badpass');

    await tester.tap(find.text(Strings.signInButton));
    await tester.pumpAndSettle();

    expect(find.text(Strings.errInvalidCredential), findsOneWidget);
  });

  testWidgets(
      'sign-in with popup-closed-by-user shows no error banner and remains on form',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    auth.signInErrorCode = 'popup-closed-by-user';

    await tester.pumpWidget(AdminApp(authService: auth, api: api));
    await tester.pumpAndSettle();

    expect(find.text(Strings.signInTitle), findsOneWidget);

    await tester.tap(find.text(Strings.signInWithGoogle));
    await tester.pumpAndSettle();

    // No error banner shown
    expect(find.text(Strings.errGenericFallback), findsNothing);
    expect(find.text(Strings.errInvalidCredential), findsNothing);
    expect(find.text(Strings.signInTitle), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
