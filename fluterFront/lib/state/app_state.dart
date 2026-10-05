import 'dart:async';
import 'dart:ui' show Locale;

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../services/api_client.dart';
import '../services/purchase_service.dart';
import '../services/telemetry.dart';
import '../utils/json.dart';

/// App-wide state: Firebase auth session + `/api/me` payload + toast messages.
class AppState extends ChangeNotifier {
  final ApiClient api = ApiClient();

  AppState() {
    Telemetry.init(api);
  }

  fb.User? user;
  bool authReady = false;
  bool firebaseAvailable = true;

  Map<String, dynamic>? profile;
  List<dynamic> families = [];
  List<dynamic> actors = [];
  List<dynamic> pendingRequests = [];
  int? loginEventId;

  String success = '';
  String error = '';
  Timer? _dismissTimer;

  /// The current localizations, kept up to date by the widget tree (see
  /// _ToastListener in main.dart). Lets context-less layers — auth actions,
  /// the API client, push — produce localized toasts. Null only before the
  /// first frame; callers fall back to English.
  AppLocalizations? l10n;

  Map<String, dynamic>? get family => families.isNotEmpty
      ? Map<String, dynamic>.from(families.first as Map)
      : null;

  int get familyId => toNum(family?['family_id']).toInt();
  bool get hasFamilies => families.isNotEmpty;

  bool get isCaregiver {
    final role =
        family?['role']?.toString() ?? profile?['role']?.toString() ?? '';
    return role.isEmpty || role == 'caregiver';
  }

  /// Backend user id (from /api/me), used to tell "my" tasks from others'.
  dynamic get userId => profile?['id'];

  /// Platform-level admin (users.platform_role). Gates the Admin entry in
  /// the profile screen only — every /api/admin call is re-checked
  /// server-side, so this is convenience, not authorization.
  bool get isPlatformAdmin => profile?['platform_role'] == 'admin';

  // ── Locale (user-selectable language, docs/i18n-plan.md) ────────

  static const String _localePrefKey = 'app_locale';

  /// Language codes the app actually ships, derived from the generated
  /// localizations (the app_*.arb files are the single source). Used to reject
  /// any stale or corrupt stored code so it never reaches the language picker.
  static Set<String> get supportedLanguageCodes =>
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();

  Locale? _locale;

  /// The user-chosen app language; null follows the device language.
  Locale? get locale => _locale;

  /// Reads the persisted language before runApp, validating it against the
  /// supported set so an unrecognized stored code falls back to the device
  /// locale instead of crashing the picker or shipping an untranslated UI.
  static Future<Locale?> loadPersistedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_localePrefKey);
    if (code != null && supportedLanguageCodes.contains(code)) {
      return Locale(code);
    }
    return null;
  }

  /// Sets the initial locale at construction time, before the first frame,
  /// without notifying (no listeners exist yet).
  void seedLocale(Locale? value) {
    _locale = value;
  }

  Future<void> setLocale(Locale? value) async {
    _locale = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_localePrefKey);
    } else {
      await prefs.setString(_localePrefKey, value.languageCode);
    }
  }

  void init() {
    if (!firebaseAvailable) {
      authReady = true;
      notifyListeners();
      return;
    }
    fb.FirebaseAuth.instance.idTokenChanges().listen((u) async {
      user = u;
      if (u != null) {
        api.token = await u.getIdToken() ?? '';
        if (!authReady) await fetchUserData();
      } else {
        api.token = '';
        loginEventId = null;
        profile = null;
        families = [];
        actors = [];
        pendingRequests = [];
      }
      authReady = true;
      notifyListeners();
    });
  }

  /// True when the last `/api/me` attempt failed for a reason that is *not*
  /// the session being invalid — the network is down, or the backend is
  /// unwell. We therefore do not know whether this user has a family, and the
  /// UI must not guess: an empty `families` list then means "unknown", not
  /// "none". See `_AuthGate` in main.dart.
  bool meLoadFailed = false;

  /// True when we are signed in but have never learned who this user is.
  /// `families` is empty because the lookup failed, not because there are
  /// none — so the app must offer a retry, never the create-a-family wizard.
  bool get profileUnknown => meLoadFailed && profile == null;

  /// Whether an error means the session itself is no longer accepted, as
  /// opposed to the request merely failing. Only this warrants signing
  /// someone out; a flaky network must never do it.
  static bool isSessionRejected(Object error) =>
      error is ApiException &&
      (error.statusCode == 401 || error.statusCode == 403);

  Future<void> fetchUserData() async {
    try {
      final data = await api.get('/api/me');
      profile = (data['user'] as Map?)?.cast<String, dynamic>();
      families = (data['families'] as List?) ?? [];
      pendingRequests = (data['pendingRequests'] as List?) ?? [];
      actors = (data['actors'] as List?) ?? [];
      meLoadFailed = false;

      if (loginEventId == null) {
        final loginData = await api.post('/api/me/login-event');
        loginEventId = toNumOrNull(loginData['eventId'])?.toInt();
      }

      // Tie the RevenueCat identity to the backend user id so webhook
      // events carry it (plan Phase 4). Fire-and-forget: purchases must
      // never block login, and the service no-ops on web.
      PurchaseService.syncIdentity(profile?['id']?.toString());
    } on ApiException catch (e) {
      if (isSessionRejected(e)) {
        // The backend rejected the session. Falling through would leave
        // `families` empty, and an empty family list sends the user to the
        // create-a-family wizard — telling someone whose session merely
        // expired that their household is gone. Sign out instead, so they
        // land on the login screen, which is the truthful thing to show.
        debugPrint('Session rejected by the backend ($e); signing out.');
        await logout();
        return;
      }
      meLoadFailed = true;
      debugPrint('Backend auth sync failed: $e');
    } catch (e) {
      meLoadFailed = true;
      debugPrint('Backend auth sync failed: $e');
    }
    notifyListeners();
  }

  // ── Auth actions ────────────────────────────────────────────────

  Future<void> login(String email, String password) async {
    clearMessages();
    try {
      final cred = await fb.FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      await _afterSignIn(cred.user!);
      setSuccess(l10n?.toastLoggedIn ?? 'Logged in successfully!');
    } catch (e) {
      setError(_authMessage(e));
      rethrow;
    }
  }

  Future<void> register(String email, String password) async {
    clearMessages();
    try {
      final cred = await fb.FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      await _afterSignIn(cred.user!);
      setSuccess(l10n?.toastAccountCreated ?? 'Account created successfully!');
    } catch (e) {
      setError(_authMessage(e));
      rethrow;
    }
  }

  Future<void> loginWithGoogle() async {
    clearMessages();
    try {
      fb.UserCredential cred;
      if (kIsWeb) {
        cred = await fb.FirebaseAuth.instance
            .signInWithPopup(fb.GoogleAuthProvider());
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) return; // user cancelled
        final googleAuth = await googleUser.authentication;
        cred = await fb.FirebaseAuth.instance.signInWithCredential(
          fb.GoogleAuthProvider.credential(
            idToken: googleAuth.idToken,
            accessToken: googleAuth.accessToken,
          ),
        );
      }
      await _afterSignIn(cred.user!);
      setSuccess(
          l10n?.toastLoggedInGoogle ?? 'Logged in with Google successfully!');
    } catch (e) {
      setError(_authMessage(e));
      rethrow;
    }
  }

  Future<void> resetPassword(String email) async {
    clearMessages();
    try {
      await fb.FirebaseAuth.instance
          .sendPasswordResetEmail(email: email.trim());
      setSuccess(l10n?.toastResetEmailSent(email.trim()) ??
          'Password reset email sent to ${email.trim()}.');
    } catch (e) {
      setError(_authMessage(e));
    }
  }

  Future<void> _afterSignIn(fb.User u) async {
    user = u;
    api.token = await u.getIdToken() ?? '';
    await fetchUserData();
  }

  Future<void> logout() async {
    clearMessages();
    try {
      if (api.token.isNotEmpty) {
        await api.post('/api/me/logout-event', {'eventId': loginEventId});
      }
    } catch (e) {
      debugPrint('Failed to safely track backend logout: $e');
    }
    await PurchaseService.logOut();
    api.token = '';
    loginEventId = null;
    await fb.FirebaseAuth.instance.signOut();
  }

  String _authMessage(Object e) {
    final l = l10n;
    if (l == null) {
      return e is fb.FirebaseAuthException ? (e.message ?? e.code) : e.toString();
    }
    if (e is fb.FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-credential':
        case 'invalid-login-credentials':
        case 'wrong-password':
        case 'user-not-found':
          return l.errAuthInvalidCredentials;
        case 'email-already-in-use':
          return l.errAuthEmailInUse;
        case 'invalid-email':
          return l.errAuthInvalidEmail;
        case 'weak-password':
          return l.errAuthWeakPassword;
        case 'too-many-requests':
          return l.errAuthTooManyRequests;
        case 'network-request-failed':
          return l.errNetwork;
        default:
          return l.errAuthGeneric;
      }
    }
    return l.errAuthGeneric;
  }

  /// Public wrapper on the error localizer, for surfaces that cannot rely on
  /// the toast: a modal bottom sheet draws over the SnackBar, so those must
  /// render the same text inline instead.
  String errorTextFor(Object e) => _localizeError(e);

  /// Turns any thrown error into a display string, localizing the API client's
  /// categorized failures; backend-authored messages pass through unchanged.
  String _localizeError(Object e) {
    final l = l10n;
    if (e is ApiException) {
      if (e.serverMessage != null) return e.serverMessage!;
      if (l == null) return e.toString();
      switch (e.kind) {
        case ApiErrorKind.timeout:
          return l.errTimeout;
        case ApiErrorKind.network:
          return l.errNetwork;
        case ApiErrorKind.requestFailed:
          return l.errRequestFailed(e.statusCode ?? 0);
        case ApiErrorKind.uploadTimeout:
          return l.errUploadTimeout;
        case ApiErrorKind.uploadFailed:
          return l.errUploadFailed(e.statusCode ?? 0);
        case ApiErrorKind.server:
          return e.toString();
      }
    }
    return e.toString();
  }

  // ── Toast messages (mirrors setSuccess / setError / runAction) ──

  Future<bool> runAction(Future<void> Function() fn,
      [String? okMessage]) async {
    clearMessages();
    try {
      await fn();
      if (okMessage != null) setSuccess(okMessage);
      return true;
    } catch (e) {
      setError(_localizeError(e));
      return false;
    }
  }

  void setSuccess(String message) {
    success = message;
    error = '';
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(milliseconds: 3500), () {
      success = '';
      notifyListeners();
    });
    notifyListeners();
  }

  void setError(String message) {
    error = message;
    success = '';
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(milliseconds: 5000), () {
      error = '';
      notifyListeners();
    });
    notifyListeners();
  }

  void clearMessages() {
    success = '';
    error = '';
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }
}
