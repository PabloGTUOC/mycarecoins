import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_front/api.dart';
import 'package:admin_front/app_state.dart';
import 'package:admin_front/auth.dart';
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
        isGoogle: true,
      ),
    );
    api = FakeAdminApi();
    state = AppState(api: api, auth: auth);
  });

  tearDown(() {
    auth.dispose();
  });

  Widget buildTriggerWidget(VoidCallback onTrigger) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildAdminTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: onTrigger,
                child: const Text('Trigger Mutation'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
      'Re-auth: 401 adminReauthRequired shows dialog; confirm retries once and succeeds',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // Queue 401 first, then success
    api.queueResponse(
      'POST',
      '/mutate',
      AdminApiException(
        statusCode: 401,
        code: 'adminReauthRequired',
        message: 'Sign in again to make changes.',
      ),
    );
    api.queueResponse('POST', '/mutate', {'ok': true});

    late BuildContext currentContext;
    await tester.pumpWidget(
      buildTriggerWidget(() async {
        await state.runMutation(
          currentContext,
          () => api.post('/mutate', {'key': 'val'}),
          successMessage: 'Mutation succeeded.',
        );
      }),
    );
    currentContext = tester.element(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    // Trigger mutation
    await tester.tap(find.text('Trigger Mutation'));
    await tester.pumpAndSettle();

    // Reauth dialog must appear
    expect(find.text(Strings.reauthRequiredTitle), findsOneWidget);
    expect(find.text(Strings.reauthRequiredBody), findsOneWidget);
    expect(find.text(Strings.confirm), findsOneWidget);
    expect(find.text(Strings.cancel), findsOneWidget);

    // Tap confirm
    await tester.tap(find.text(Strings.confirm));
    await tester.pumpAndSettle();

    // Confirm that reauth occurred
    expect(auth.googleReauthCount, 1);

    // Confirm that the mutation retried once (2 calls total)
    final mutateCalls = api.callHistory.where((c) => c.path == '/mutate').toList();
    expect(mutateCalls.length, 2);

    // Confirm success message
    expect(find.text('Mutation succeeded.'), findsOneWidget);
  });

  testWidgets(
      'Re-auth: 401 adminReauthRequired shows dialog; cancel does not retry and notifies user',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.queueResponse(
      'POST',
      '/mutate',
      AdminApiException(
        statusCode: 401,
        code: 'adminReauthRequired',
        message: 'Sign in again to make changes.',
      ),
    );
    api.queueResponse('POST', '/mutate', {'ok': true});

    late BuildContext currentContext;
    await tester.pumpWidget(
      buildTriggerWidget(() async {
        await state.runMutation(
          currentContext,
          () => api.post('/mutate', {'key': 'val'}),
          successMessage: 'Mutation succeeded.',
        );
      }),
    );
    currentContext = tester.element(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    // Trigger mutation
    await tester.tap(find.text('Trigger Mutation'));
    await tester.pumpAndSettle();

    // Reauth dialog appears
    expect(find.text(Strings.reauthRequiredTitle), findsOneWidget);

    // Tap Cancel
    await tester.tap(find.text(Strings.cancel));
    await tester.pumpAndSettle();

    // Reauth did not occur
    expect(auth.googleReauthCount, 0);

    // Mutation was NOT retried (only 1 call total)
    final mutateCalls = api.callHistory.where((c) => c.path == '/mutate').toList();
    expect(mutateCalls.length, 1);

    // User is notified that change was cancelled
    expect(find.text(Strings.reauthCancelled), findsOneWidget);
  });

  testWidgets(
      'Re-auth: wrong password keeps dialog open with inline error, succeeds on retry',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final emailAuth = FakeAuthService(
      initialUser: const OperatorUser(
        uid: 'op_email',
        email: 'operator@carecoins.app',
        isGoogle: false,
      ),
    );
    emailAuth.expectedPassword = 'correct_password';

    final emailState = AppState(api: api, auth: emailAuth);

    api.queueResponse(
      'POST',
      '/mutate',
      AdminApiException(
        statusCode: 401,
        code: 'adminReauthRequired',
        message: 'Sign in again to make changes.',
      ),
    );
    api.queueResponse('POST', '/mutate', {'ok': true});

    late BuildContext currentContext;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: emailState,
        child: MaterialApp(
          theme: buildAdminTheme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await emailState.runMutation(
                      currentContext,
                      () => api.post('/mutate', {'key': 'val'}),
                      successMessage: 'Mutation succeeded.',
                    );
                  },
                  child: const Text('Trigger Mutation'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    currentContext = tester.element(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    // Trigger mutation
    await tester.tap(find.text('Trigger Mutation'));
    await tester.pumpAndSettle();

    // Reauth dialog appears with password field
    expect(find.text(Strings.reauthRequiredTitle), findsOneWidget);
    expect(find.text(Strings.reauthPasswordPrompt), findsOneWidget);

    final passField = find.byType(TextField);
    expect(passField, findsOneWidget);

    // Enter wrong password
    await tester.enterText(passField, 'wrong_pass');
    await tester.tap(find.text(Strings.confirm));
    await tester.pumpAndSettle();

    // Dialog must remain open and display inline error
    expect(find.text(Strings.reauthRequiredTitle), findsOneWidget);
    expect(find.text(Strings.errWrongPasswordRetry), findsOneWidget);
    expect(emailAuth.passwordReauthCount, 1);

    // Enter correct password and confirm
    await tester.enterText(passField, 'correct_password');
    await tester.tap(find.text(Strings.confirm));
    await tester.pumpAndSettle();

    // Dialog is now closed, reauth succeeded (2 attempts), mutation retried and succeeded
    expect(find.text(Strings.reauthRequiredTitle), findsNothing);
    expect(emailAuth.passwordReauthCount, 2);
    expect(find.text('Mutation succeeded.'), findsOneWidget);

    emailAuth.dispose();
  });
}
