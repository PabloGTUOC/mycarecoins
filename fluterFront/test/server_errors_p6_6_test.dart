import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/l10n/server_errors.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';

void main() {
  /// Builds an AppState with its l10n handle bound to [locale], matching
  /// error_localization_test.dart.
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

  testWidgets(
      'every code in error-codes.md localizes non-null except deliberately null ones',
      (tester) async {
    final app = await boundApp(tester, const Locale('en'));
    final l = app.l10n!;

    final file = File('../docs/error-codes.md');
    expect(file.existsSync(), isTrue, reason: 'docs/error-codes.md must exist');
    final lines = file.readAsLinesSync();

    final codes = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('| `')) {
        final parts = trimmed
            .split('|')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) {
          final code = parts[0].replaceAll('`', '');
          codes.add(code);
        }
      }
    }

    expect(codes, isNotEmpty);

    // List of deliberately null codes with reasons:
    final deliberatelyNull = <String, String>{
      'adminOnly':
          'Admin access is web-only / CLI-only and out of scope for mobile (brief decision 3).',
      // Operator console API only (docs/management-platform-plan.md); the
      // subscriber app never talks to it.
      'accessInvalid': 'Operator console API only.',
      'accessMissing': 'Operator console API only.',
      'adminReauthRequired': 'Operator console API only.',
      'appStoreNotConfigured': 'Operator console API only.',
      'appStoreRejected': 'Operator console API only.',
      'appStoreUnavailable': 'Operator console API only.',
      'rateLimited': 'Operator console API only.',
    };

    final dummyParams = <String, dynamic>{
      'title': 'Test Activity',
      'hours': 24,
      'minutes': 15,
      'max': 60,
      'occurrences': 2,
      'escrow': 10,
      'index': 0,
      'reason': 'test reason',
      'field': 'testField',
      'role': 'caregiver',
      'reasonCode': 'activityRescheduleOverlap',
      'reasonParams': <String, dynamic>{'title': 'Overlap Task'},
    };

    for (final code in codes) {
      final result = localizeServerError(l, code, dummyParams);
      if (deliberatelyNull.containsKey(code)) {
        expect(result, isNull,
            reason:
                'code $code is deliberately mapped to null: ${deliberatelyNull[code]}');
      } else {
        expect(result, isNotNull,
            reason: 'code $code in error-codes.md must return a localized string');
      }
    }

    app.dispose();
  });

  testWidgets('Spanish localization for error codes', (tester) async {
    final app = await boundApp(tester, const Locale('es'));
    final l = app.l10n!;

    // activityNotFound (code without params) -> Spanish string
    final notFound = localizeServerError(l, 'activityNotFound', const {});
    expect(notFound, 'Actividad no encontrada.');

    // code with a title param -> Spanish string containing the title
    final overlap =
        localizeServerError(l, 'scheduleOverlap', {'title': 'Dentista'});
    expect(overlap, contains('Dentista'));
    expect(overlap, 'Ya tienes "Dentista" programado durante este horario.');

    // personalTimeSeriesBlocked with a known reasonCode -> both halves in Spanish
    final blocked = localizeServerError(l, 'personalTimeSeriesBlocked', {
      'occurrences': 3,
      'reasonCode': 'activityRescheduleOverlap',
      'reasonParams': {'title': 'Dentista'},
    });
    expect(blocked, isNotNull);
    expect(blocked, contains('Dentista'));
    expect(blocked, contains('Ninguna de las 3 repeticiones encaja'));
    expect(blocked, contains('Ya tienes "Dentista" programado'));

    // personalTimeSeriesBlocked with an unknown reasonCode -> null (fallback to English)
    final blockedUnknown = localizeServerError(l, 'personalTimeSeriesBlocked', {
      'occurrences': 3,
      'reasonCode': 'unknownReasonCode',
      'reasonParams': {},
    });
    expect(blockedUnknown, isNull);

    app.dispose();
  });

  testWidgets('_localizeError behavior via app.errorTextFor', (tester) async {
    final app = await boundApp(tester, const Locale('es'));

    // ApiException with unknown errorCode -> falls back to serverMessage
    final unknownErr = ApiException(ApiErrorKind.server,
        statusCode: 409,
        serverMessage: 'English server message',
        errorCode: 'unknownThing');
    expect(app.errorTextFor(unknownErr), 'English server message');

    // ApiException with a known code -> translated
    final knownErr = ApiException(ApiErrorKind.server,
        statusCode: 404,
        serverMessage: 'Activity not found',
        errorCode: 'activityNotFound');
    expect(app.errorTextFor(knownErr), 'Actividad no encontrada.');

    // 500 with a code -> errServerTrouble
    final server500WithCode = ApiException(ApiErrorKind.server,
        statusCode: 500,
        serverMessage: 'Internal server error',
        errorCode: 'activityNotFound');
    expect(app.errorTextFor(server500WithCode),
        'Algo salió mal por nuestra parte. Inténtalo de nuevo en un momento.');

    // 500 with code 'internal' -> errServerTrouble
    final internal500 = ApiException(ApiErrorKind.server,
        statusCode: 500,
        serverMessage: 'Internal server error',
        errorCode: 'internal');
    expect(app.errorTextFor(internal500),
        'Algo salió mal por nuestra parte. Inténtalo de nuevo en un momento.');

    app.dispose();
  });
}
