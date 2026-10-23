import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/services/extensions_bridge.dart';
import 'package:carecoins_flutter/state/app_state.dart';

/// When `/api/me` failed, the app used to swallow the error and leave
/// `families` empty — and an empty family list routes to the create-a-family
/// wizard. So an expired session, or a dropped connection, told someone with
/// an existing household to set up a new one.
///
/// The fix splits one failure into two: a rejected *session* signs you out,
/// anything else leaves the session alone and offers a retry. These guard that
/// split, because getting it backwards is silent and nasty in both directions
/// — logging people out on a flaky train, or hiding a dead session behind a
/// setup wizard.
void main() {
  group('isSessionRejected', () {
    test('401 and 403 mean the session is gone', () {
      for (final code in [401, 403]) {
        expect(
          AppState.isSessionRejected(
              ApiException(ApiErrorKind.server, statusCode: code)),
          isTrue,
          reason: '$code must sign the user out',
        );
      }
    });

    test('a flaky connection never signs anyone out', () {
      final transient = [
        ApiException(ApiErrorKind.network),
        ApiException(ApiErrorKind.timeout),
        ApiException(ApiErrorKind.server, statusCode: 500),
        ApiException(ApiErrorKind.server, statusCode: 503),
        ApiException(ApiErrorKind.requestFailed, statusCode: 404),
      ];
      for (final e in transient) {
        expect(AppState.isSessionRejected(e), isFalse,
            reason: '$e must not end the session');
      }
    });

    test('a non-API error is not a rejected session', () {
      expect(AppState.isSessionRejected(Exception('boom')), isFalse);
      expect(AppState.isSessionRejected(StateError('nope')), isFalse);
    });

    test('a 401 carrying a backend message is still recognised', () {
      // The backend always sends {"error": "..."} on 401, which routes through
      // ApiErrorKind.server. The status code must survive that path, or the
      // rejection is invisible — this is exactly what the bug was.
      final e = ApiException(ApiErrorKind.server,
          statusCode: 401, serverMessage: 'Invalid or expired token.');
      expect(AppState.isSessionRejected(e), isTrue);
    });
  });

  group('profileUnknown', () {
    test('is false before anything has failed', () {
      expect(AppState().profileUnknown, isFalse);
    });

    test('is true when the lookup failed and we never got a profile', () {
      final app = AppState()..meLoadFailed = true;
      expect(app.profile, isNull);
      expect(app.profileUnknown, isTrue,
          reason: 'an unknown state must offer a retry, not onboarding');
    });

    test('is false once a profile is known, so a later blip does not blank the app', () {
      final app = AppState()
        ..profile = {'id': 1}
        ..meLoadFailed = true;
      expect(app.profileUnknown, isFalse);
    });
  });

  group('logout', () {
    test('calls DELETE /api/me/device-keys and channel clear', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final channelCalls = <String>[];
      messenger.setMockMethodCallHandler(ExtensionsBridge.channel, (call) async {
        channelCalls.add(call.method);
        return null;
      });

      final api = _FakeLogoutApi()..token = 'test_token';
      final app = AppState(api: api);

      try {
        await app.logout();
      } catch (_) {
        // AppState.logout() reaches fb.FirebaseAuth.instance.signOut() at the end,
        // which throws [core/no-app] when Firebase is not initialized.
      } finally {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(ExtensionsBridge.channel, null);
      }

      expect(api.deletedPath, '/api/me/device-keys');
      expect(channelCalls.contains('clear'), isTrue);
    });
  });
}

class _FakeLogoutApi extends ApiClient {
  String? deletedPath;

  @override
  Future<dynamic> post(String path, [Object? body]) async => {};

  @override
  Future<dynamic> delete(String path, [Object? body]) async {
    deletedPath = path;
    return {};
  }
}
