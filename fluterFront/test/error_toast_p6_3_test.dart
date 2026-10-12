import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/main.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';

void main() {
  Future<AppState> boundApp(WidgetTester tester, [Locale locale = const Locale('en')]) async {
    final app = AppState();
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        app.l10n = AppLocalizations.of(context);
        return const SizedBox();
      }),
    ));
    await tester.pumpAndSettle();
    return app;
  }

  Widget buildToastApp(AppState app, [Locale locale = const Locale('en')]) {
    return ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ToastListener(
          child: Scaffold(
            body: Center(child: Text('Home')),
          ),
        ),
      ),
    );
  }

  group('P6-3: _localizeError through errorTextFor', () {
    testWidgets('500 server error with serverMessage returns errServerTrouble text', (tester) async {
      final app = await boundApp(tester, const Locale('en'));
      final err = ApiException(
        ApiErrorKind.server,
        statusCode: 500,
        serverMessage: 'Failed to approve activity.',
      );
      expect(app.errorTextFor(err), 'Something went wrong on our side. Try again in a moment.');
      app.dispose();
    });

    testWidgets('status 409 with a serverMessage returns the serverMessage', (tester) async {
      final app = await boundApp(tester, const Locale('en'));
      final err = ApiException(
        ApiErrorKind.server,
        statusCode: 409,
        serverMessage: 'Activity already accepted',
      );
      expect(app.errorTextFor(err), 'Activity already accepted');
      app.dispose();
    });

    testWidgets('requestFailed with status 404 returns errRequestFailed text', (tester) async {
      final app = await boundApp(tester, const Locale('en'));
      final err = ApiException(
        ApiErrorKind.requestFailed,
        statusCode: 404,
      );
      expect(app.errorTextFor(err), "That didn't work (error 404). Try again, or reload the screen.");
      app.dispose();
    });

    testWidgets('server error without serverMessage returns errServerTrouble', (tester) async {
      final app = await boundApp(tester, const Locale('en'));
      final err = ApiException(ApiErrorKind.server);
      expect(app.errorTextFor(err), 'Something went wrong on our side. Try again in a moment.');
      app.dispose();
    });

    testWidgets('500 error in Spanish returns localized errServerTrouble', (tester) async {
      final app = await boundApp(tester, const Locale('es'));
      final err = ApiException(
        ApiErrorKind.server,
        statusCode: 500,
        serverMessage: 'Failed to approve activity.',
      );
      expect(app.errorTextFor(err), 'Algo salió mal por nuestra parte. Inténtalo de nuevo en un momento.');
      app.dispose();
    });
  });

  group('P6-3: runAction and errorRetry', () {
    testWidgets('throws 500 sets errorRetry != null', (tester) async {
      final app = await boundApp(tester);
      final ok = await app.runAction(() async {
        throw ApiException(ApiErrorKind.server, statusCode: 500);
      });
      expect(ok, isFalse);
      expect(app.errorRetry, isNotNull);
      app.dispose();
    });

    testWidgets('throws 409 sets errorRetry == null', (tester) async {
      final app = await boundApp(tester);
      final ok = await app.runAction(() async {
        throw ApiException(ApiErrorKind.server, statusCode: 409, serverMessage: 'Conflict');
      });
      expect(ok, isFalse);
      expect(app.errorRetry, isNull);
      app.dispose();
    });

    testWidgets('calling errorRetry re-runs the action and clears error on success', (tester) async {
      final app = await boundApp(tester);
      int attempts = 0;

      final ok = await app.runAction(() async {
        attempts++;
        if (attempts == 1) {
          throw ApiException(ApiErrorKind.server, statusCode: 500);
        }
      });

      expect(ok, isFalse);
      expect(attempts, 1);
      expect(app.error, isNotEmpty);
      expect(app.errorRetry, isNotNull);

      await app.errorRetry!();

      expect(attempts, 2);
      expect(app.error, isEmpty);
      expect(app.errorRetry, isNull);
      app.dispose();
    });

    testWidgets('error auto-dismiss timer is 10 seconds', (tester) async {
      final app = await boundApp(tester);
      await app.runAction(() async {
        throw ApiException(ApiErrorKind.server, statusCode: 500);
      });

      expect(app.error, isNotEmpty);
      expect(app.errorRetry, isNotNull);

      await tester.pump(const Duration(seconds: 5));
      expect(app.error, isNotEmpty);
      expect(app.errorRetry, isNotNull);

      await tester.pump(const Duration(seconds: 5));
      expect(app.error, isEmpty);
      expect(app.errorRetry, isNull);

      app.dispose();
    });
  });

  group('P6-3: ToastListener widget', () {
    testWidgets('error with retry shows "Retry" and close icon; tapping Retry calls function', (tester) async {
      final app = AppState();
      await tester.pumpWidget(buildToastApp(app));
      await tester.pumpAndSettle();

      int attempts = 0;
      await app.runAction(() async {
        attempts++;
        if (attempts == 1) {
          throw ApiException(ApiErrorKind.server, statusCode: 500);
        }
      });

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong on our side. Try again in a moment.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(app.error, isEmpty);
      expect(app.errorRetry, isNull);

      app.dispose();
    });

    testWidgets('error without retry shows close icon but no Retry action', (tester) async {
      final app = AppState();
      await tester.pumpWidget(buildToastApp(app));
      await tester.pumpAndSettle();

      await app.runAction(() async {
        throw ApiException(ApiErrorKind.server, statusCode: 409, serverMessage: 'Already exists');
      });

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Already exists'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.byIcon(Icons.close), findsOneWidget);

      app.dispose();
    });
  });
}
