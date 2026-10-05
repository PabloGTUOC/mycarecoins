import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'screens/landing_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/ui.dart';

/// Point auth at the Firebase Auth Emulator for local testing, matching the
/// backend's `npm run dev:test`. Example:
///   flutter run --dart-define=AUTH_EMULATOR=localhost:9099
const String _kAuthEmulator = String.fromEnvironment('AUTH_EMULATOR');

/// Built once and reused across rebuilds — buildAppTheme() constructs a full
/// ThemeData (ColorScheme.fromSeed + GoogleFonts), which must not run on every
/// AppState change. Lazily initialized on first access.
final ThemeData _appTheme = buildAppTheme();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var firebaseAvailable = true;
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    if (_kAuthEmulator.isNotEmpty) {
      final parts = _kAuthEmulator.split(':');
      await fb.FirebaseAuth.instance.useAuthEmulator(
          parts[0], parts.length > 1 ? int.parse(parts[1]) : 9099);
    }
  } catch (e) {
    // Keep the app bootable before `flutterfire configure` has been run.
    firebaseAvailable = false;
    debugPrint('Firebase init failed (run flutterfire configure): $e');
  }

  // Read the persisted language before the first frame so the UI never paints
  // in the device locale and then visibly snaps to the chosen one.
  final initialLocale = await AppState.loadPersistedLocale();

  runApp(CareCoinsApp(
      firebaseAvailable: firebaseAvailable, initialLocale: initialLocale));
}

class CareCoinsApp extends StatelessWidget {
  final bool firebaseAvailable;
  final Locale? initialLocale;
  const CareCoinsApp(
      {super.key, required this.firebaseAvailable, this.initialLocale});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()
        ..firebaseAvailable = firebaseAvailable
        ..seedLocale(initialLocale)
        ..init(),
      // Select only the locale: unrelated AppState changes (toasts, auth,
      // profile refreshes) must not rebuild MaterialApp or its theme.
      child: Selector<AppState, Locale?>(
        selector: (_, app) => app.locale,
        builder: (context, locale, _) => MaterialApp(
          title: 'CareCoins',
          debugShowCheckedModeBanner: false,
          theme: _appTheme,
          // User-chosen language (persisted); null follows the device.
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // Fixed-height chrome (bottom tabs, timeline chips) breaks beyond
          // ~130% OS font scale; clamp until those containers are flexible.
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                  textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3)),
              child: child!,
            );
          },
          home: const _ToastListener(child: _AuthGate()),
        ),
      ),
    );
  }
}

/// Shows AppState success/error messages as snackbars app-wide, so toasts
/// also reach logged-out screens (login errors, password-reset feedback).
class _ToastListener extends StatefulWidget {
  final Widget child;
  const _ToastListener({required this.child});

  @override
  State<_ToastListener> createState() => _ToastListenerState();
}

class _ToastListenerState extends State<_ToastListener> {
  String _lastToast = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // Keep AppState's localizations current so context-less layers (auth,
    // API client, push) can localize their toasts. This widget sits under
    // MaterialApp and rebuilds on locale change, so l10n stays fresh.
    app.l10n = AppLocalizations.of(context);
    final msg = app.error.isNotEmpty ? app.error : app.success;
    if (msg.isEmpty) {
      _lastToast = '';
    } else if (msg != _lastToast) {
      _lastToast = msg;
      final isError = app.error.isNotEmpty;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(msg),
            backgroundColor: isError ? AppColors.danger : AppColors.success,
            duration: Duration(milliseconds: isError ? 5000 : 3500),
          ));
      });
    }
    return widget.child;
  }
}

/// The auth gate: loading screen until auth is ready,
/// landing → login for guests, onboarding when the user has no family,
/// else the shell.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _showLogin = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = AppLocalizations.of(context);

    if (!app.authReady) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Text(l.loadingApp,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
        ),
      );
    }
    if (app.user == null) {
      if (!_showLogin) {
        return LandingScreen(
            onSignIn: () => setState(() => _showLogin = true));
      }
      return Stack(
        children: [
          const LoginScreen(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton.icon(
                onPressed: () => setState(() => _showLogin = false),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(l.back),
              ),
            ),
          ),
        ],
      );
    }
    // We are signed in but have never successfully loaded who this user is.
    // `families` is empty because the request failed, not because there are
    // none — routing to onboarding here would invite someone with an existing
    // household to create a second one. Offer a retry instead. A later
    // failure, once the profile is known, is left alone: the app keeps
    // working on what it already has rather than blanking mid-session.
    if (app.profileUnknown) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(child: LoadErrorState(onRetry: app.fetchUserData)),
      );
    }
    if (!app.hasFamilies) return const OnboardingScreen();
    return const Shell();
  }
}
