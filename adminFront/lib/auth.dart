import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fb;

/// Lightweight user model for the operator console.
class OperatorUser {
  final String uid;
  final String? email;
  final bool isGoogle;

  const OperatorUser({
    required this.uid,
    this.email,
    this.isGoogle = false,
  });
}

/// Auth exception carrying an error code (such as FirebaseAuthException.code).
class AuthException implements Exception {
  final String code;
  final String? message;

  const AuthException(this.code, [this.message]);

  @override
  String toString() => 'AuthException($code: $message)';
}


/// Abstract auth service interface so tests can run without real Firebase.
abstract class AuthService {
  Stream<OperatorUser?> get authStateChanges;
  OperatorUser? get currentUser;

  Future<void> signInWithGoogle();
  Future<void> signInWithEmailPassword(String email, String password);
  Future<void> signOut();

  Future<void> reauthenticateWithGoogle();
  Future<void> reauthenticateWithPassword(String password);

  Future<String?> getIdToken({bool forceRefresh = false});
}

/// Real Firebase Auth implementation.
class FirebaseAuthService implements AuthService {
  final fb.FirebaseAuth _auth;

  FirebaseAuthService({fb.FirebaseAuth? auth})
      : _auth = auth ?? fb.FirebaseAuth.instance;

  OperatorUser? _mapUser(fb.User? user) {
    if (user == null) return null;
    final isGoogle =
        user.providerData.any((p) => p.providerId == 'google.com');
    return OperatorUser(
      uid: user.uid,
      email: user.email,
      isGoogle: isGoogle,
    );
  }

  @override
  Stream<OperatorUser?> get authStateChanges =>
      _auth.authStateChanges().map(_mapUser);

  @override
  OperatorUser? get currentUser => _mapUser(_auth.currentUser);

  @override
  Future<void> signInWithGoogle() async {
    final provider = fb.GoogleAuthProvider();
    await _auth.signInWithPopup(provider);
  }

  @override
  Future<void> signInWithEmailPassword(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
  }

  @override
  Future<void> reauthenticateWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No current user to reauthenticate.');
    final provider = fb.GoogleAuthProvider();
    await user.reauthenticateWithPopup(provider);
  }

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception('No current user email to reauthenticate.');
    }
    final cred = fb.EmailAuthProvider.credential(
      email: user.email!,
      password: password,
    );
    await user.reauthenticateWithCredential(cred);
  }

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return await user.getIdToken(forceRefresh);
  }
}
