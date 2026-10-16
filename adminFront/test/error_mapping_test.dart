import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:admin_front/api.dart';
import 'package:admin_front/strings.dart';

void main() {
  group('Error mapping', () {
    test('all documented server error codes map to distinct English messages', () {
      expect(Strings.errorFor(code: 'adminOnly'), Strings.errAdminOnly);
      expect(Strings.errorFor(code: 'adminReauthRequired'),
          Strings.errAdminReauthRequired);
      expect(Strings.errorFor(code: 'accessMissing'), Strings.errAccessMissing);
      expect(Strings.errorFor(code: 'accessInvalid'), Strings.errAccessInvalid);
      expect(
          Strings.errorFor(code: 'authMissingToken'), Strings.errAuthMissingToken);
      expect(Strings.errorFor(code: 'notFound'), Strings.errNotFound);
      expect(Strings.errorFor(statusCode: 404), Strings.errNotFound);
      expect(Strings.errorFor(code: 'rateLimited'), Strings.errRateLimited);
      expect(Strings.errorFor(statusCode: 429), Strings.errRateLimited);
    });

    test('unknown error code falls back to generic message', () {
      expect(
        Strings.errorFor(code: 'completelyUnknownErrorCode123'),
        Strings.errGenericFallback,
      );
      expect(
        Strings.errorFor(),
        Strings.errGenericFallback,
      );
    });

    test('unknown code with non-empty server message returns the server message', () {
      expect(
        Strings.errorFor(
          code: 'unknown_code',
          serverMessage: 'Custom validation message from server.',
        ),
        'Custom validation message from server.',
      );
    });

    test('rateLimited takes precedence over server message', () {
      expect(
        Strings.errorFor(
          statusCode: 429,
          serverMessage: 'Custom message',
        ),
        Strings.errRateLimited,
      );
    });

    test('429 with code rateLimited shows the rate-limit message', () async {
      final mock = MockClient((request) async {
        return http.Response(
          '{"error": "Too many requests. Please try again later.", "code": "rateLimited"}',
          429,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = HttpAdminApi(
        getToken: ({bool forceRefresh = false}) async => 'token',
        client: mock,
        baseUrl: 'http://localhost',
      );

      try {
        await api.get('/families');
        fail('Should have thrown AdminApiException');
      } on AdminApiException catch (e) {
        expect(e.statusCode, 429);
        expect(e.code, 'rateLimited');
        expect(
          Strings.errorFor(
            code: e.code,
            statusCode: e.statusCode,
            serverMessage: e.message,
          ),
          Strings.errRateLimited,
        );
      }
    });

    test('FirebaseAuthException codes map to English messages or dismissals', () {
      expect(Strings.authErrorForCode('invalid-credential'),
          Strings.errInvalidCredential);
      expect(Strings.authErrorForCode('wrong-password'),
          Strings.errInvalidCredential);
      expect(Strings.authErrorForCode('user-not-found'),
          Strings.errInvalidCredential);
      expect(Strings.authErrorForCode('invalid-email'), Strings.errInvalidEmail);
      expect(Strings.authErrorForCode('user-disabled'), Strings.errUserDisabled);
      expect(Strings.authErrorForCode('too-many-requests'),
          Strings.errTooManyRequests);
      expect(Strings.authErrorForCode('network-request-failed'),
          Strings.errNetworkRequestFailed);
      expect(Strings.authErrorForCode('popup-closed-by-user'), isNull);
      expect(Strings.authErrorForCode('cancelled-popup-request'), isNull);
      expect(Strings.authErrorForCode('popup-blocked'), Strings.errPopupBlocked);
      expect(Strings.authErrorForCode('unknown-code'),
          Strings.errGenericFallback);
    });
  });
}
