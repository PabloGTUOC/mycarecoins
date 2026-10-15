import 'dart:async';
import 'package:admin_front/api.dart';
import 'package:admin_front/auth.dart';

class FakeAuthService implements AuthService {
  final _controller = StreamController<OperatorUser?>.broadcast();
  OperatorUser? _user;

  int googleReauthCount = 0;
  int passwordReauthCount = 0;
  bool shouldFailReauth = false;
  String? signInErrorCode;
  String? reauthErrorCode;
  String? expectedPassword;

  FakeAuthService({OperatorUser? initialUser}) : _user = initialUser;

  @override
  Stream<OperatorUser?> get authStateChanges async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  OperatorUser? get currentUser => _user;

  void setUser(OperatorUser? user) {
    _user = user;
    _controller.add(user);
  }

  @override
  Future<void> signInWithGoogle() async {
    if (signInErrorCode != null) {
      throw AuthException(signInErrorCode!);
    }
    setUser(const OperatorUser(
      uid: 'fake_google_uid',
      email: 'operator@carecoins.app',
      isGoogle: true,
    ));
  }

  @override
  Future<void> signInWithEmailPassword(String email, String password) async {
    if (signInErrorCode != null) {
      throw AuthException(signInErrorCode!);
    }
    setUser(OperatorUser(
      uid: 'fake_email_uid',
      email: email,
      isGoogle: false,
    ));
  }

  @override
  Future<void> signOut() async {
    setUser(null);
  }

  @override
  Future<void> reauthenticateWithGoogle() async {
    googleReauthCount++;
    if (reauthErrorCode != null) {
      throw AuthException(reauthErrorCode!);
    }
    if (shouldFailReauth) throw Exception('Google reauth failed');
  }

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    passwordReauthCount++;
    if (expectedPassword != null && password != expectedPassword) {
      throw const AuthException('wrong-password', 'Wrong password');
    }
    if (reauthErrorCode != null) {
      throw AuthException(reauthErrorCode!);
    }
    if (shouldFailReauth) throw Exception('Password reauth failed');
  }

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    return 'fake_token';
  }

  void dispose() {
    _controller.close();
  }
}

class FakeAdminApi implements AdminApi {
  final Map<String, dynamic> responses = {};
  final List<AdminApiCall> callHistory = [];
  final Map<String, List<dynamic>> responseQueues = {};

  void queueResponse(String method, String pathPrefix, dynamic responseOrException) {
    final key = '$method:$pathPrefix';
    responseQueues.putIfAbsent(key, () => []).add(responseOrException);
  }

  dynamic _dequeueOrRespond(String method, String path, [dynamic body]) {
    callHistory.add(AdminApiCall(method: method, path: path, body: body));

    for (final entry in responseQueues.entries) {
      final parts = entry.key.split(':');
      if (parts[0] == method && path.startsWith(parts[1])) {
        if (entry.value.isNotEmpty) {
          final next = entry.value.removeAt(0);
          if (next is Exception) throw next;
          return next as Map<String, dynamic>;
        }
      }
    }

    // Direct lookup or prefix lookup
    if (responses.containsKey('$method:$path')) {
      final res = responses['$method:$path'];
      if (res is Exception) throw res;
      return res as Map<String, dynamic>;
    }

    for (final entry in responses.entries) {
      final parts = entry.key.split(':');
      if (parts[0] == method && path.startsWith(parts[1])) {
        final res = entry.value;
        if (res is Exception) throw res;
        return res as Map<String, dynamic>;
      }
    }

    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> get(String path) async {
    return _dequeueOrRespond('GET', path);
  }

  @override
  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) async {
    return _dequeueOrRespond('POST', path, body);
  }

  @override
  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    return _dequeueOrRespond('PATCH', path, body);
  }

  @override
  Future<Map<String, dynamic>> delete(String path) async {
    return _dequeueOrRespond('DELETE', path);
  }
}

class AdminApiCall {
  final String method;
  final String path;
  final dynamic body;

  AdminApiCall({
    required this.method,
    required this.path,
    this.body,
  });

  @override
  String toString() => '$method $path body: $body';
}
