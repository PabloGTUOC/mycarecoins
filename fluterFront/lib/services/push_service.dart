import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../state/app_state.dart';

/// FCM permission handling, token registration against POST/DELETE
/// /api/me/fcm-token and the foreground message listener (surfaced as a
/// toast via AppState).
///
/// The VAPID key is the public web-push certificate; override with --dart-define=FIREBASE_VAPID_KEY=…
const String _kVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY',
    defaultValue:
        'BIK0CfHGGpSUAOU4eGqAUeff_kIXjJuPL7_UMouGjy0i_jSnpZGyiCA8I874e2jxMhwDuhNh0rxPCXkX_gi9VSA');

class PushService {
  PushService._();

  static String? _currentToken;
  static bool _foregroundListenerActive = false;

  /// Whether notification permission is currently granted.
  static Future<bool> get granted async {
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (_) {
      return false;
    }
  }

  /// Silent start-up sync: if permission is already
  /// granted, refresh the token registration and attach the listener.
  static Future<void> init(AppState app) async {
    if (!app.firebaseAvailable) return;
    try {
      if (!await granted) return;
      await _upsertToken(app);
      _setupForegroundListener(app);
    } catch (e) {
      debugPrint('FCM init error: $e');
    }
  }

  /// Permission prompt + registration.
  /// Returns true when permission ended up granted.
  static Future<bool> enable(AppState app) async {
    if (!app.firebaseAvailable) {
      app.setError(app.l10n?.errPushUnavailable ??
          'Push is unavailable until Firebase is configured.');
      return false;
    }
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return false;
      }
      await _upsertToken(app);
      _setupForegroundListener(app);
      return true;
    } catch (e) {
      debugPrint('FCM token error: $e');
      app.setError(app.l10n?.errPushEnableFailed('$e') ??
          'Could not enable notifications: $e');
      return false;
    }
  }

  /// Unregisters this device's token.
  static Future<void> disable(AppState app) async {
    final token = _currentToken;
    if (token == null) return;
    try {
      await app.api.delete('/api/me/fcm-token', {'token': token});
      await FirebaseMessaging.instance.deleteToken();
      _currentToken = null;
    } catch (e) {
      debugPrint('FCM disable error: $e');
    }
  }

  static Future<void> _upsertToken(AppState app) async {
    final token = await FirebaseMessaging.instance
        .getToken(vapidKey: kIsWeb ? _kVapidKey : null);
    if (token != null && token != _currentToken) {
      _currentToken = token;
      await app.api.post('/api/me/fcm-token', {'token': token});
    }
  }

  static void _setupForegroundListener(AppState app) {
    if (_foregroundListenerActive) return;
    _foregroundListenerActive = true;
    FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title;
      final body = message.notification?.body;
      if (title == null) return;
      app.setSuccess(body == null ? '🔔 $title' : '🔔 $title: $body');
    });
  }
}
