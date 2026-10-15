import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'app_state.dart';
import 'auth.dart';
import 'firebase_options.dart';
import 'screens/shell.dart';
import 'strings.dart';
import 'theme.dart';

const String _kAuthEmulator = String.fromEnvironment('AUTH_EMULATOR');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (_kAuthEmulator.isNotEmpty) {
    final parts = _kAuthEmulator.split(':');
    await fb.FirebaseAuth.instance.useAuthEmulator(
      parts[0],
      parts.length > 1 ? int.parse(parts[1]) : 9099,
    );
  }

  final authService = FirebaseAuthService();
  final api = HttpAdminApi(
    getToken: ({bool forceRefresh = false}) =>
        authService.getIdToken(forceRefresh: forceRefresh),
  );

  runApp(
    AdminApp(
      authService: authService,
      api: api,
    ),
  );
}

class AdminApp extends StatelessWidget {
  final AuthService authService;
  final AdminApi api;

  const AdminApp({
    super.key,
    required this.authService,
    required this.api,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(api: api, auth: authService),
      child: MaterialApp(
        title: Strings.appTitle,
        debugShowCheckedModeBanner: false,
        theme: buildAdminTheme(),
        home: const Shell(),
      ),
    );
  }
}
