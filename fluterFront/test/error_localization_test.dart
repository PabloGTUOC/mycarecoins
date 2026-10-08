import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';

/// Locks in review fixes 3 & 4: the API client's categorized failures reach the
/// toast in the active language, while backend-authored messages pass through.
void main() {
  /// Builds an AppState with its l10n handle bound to [locale], the way
  /// _ToastListener does at runtime.
  Future<AppState> boundApp(WidgetTester tester, Locale locale) async {
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

  testWidgets('client-side API errors are localized to the active language',
      (tester) async {
    final app = await boundApp(tester, const Locale('es'));

    await app.runAction(() async => throw ApiException(ApiErrorKind.network));
    expect(app.error, 'Error de red. Comprueba tu conexión.');

    await app.runAction(
        () async => throw ApiException(ApiErrorKind.requestFailed, statusCode: 500));
    expect(app.error, 'La solicitud falló (500)');

    app.dispose(); // cancels the pending toast-dismiss timer
  });

  testWidgets('backend-authored messages pass through unchanged',
      (tester) async {
    final app = await boundApp(tester, const Locale('fr'));

    await app.runAction(() async => throw ApiException(ApiErrorKind.server,
        serverMessage: 'Family not found'));
    expect(app.error, 'Family not found');

    app.dispose(); // cancels the pending toast-dismiss timer
  });
}
