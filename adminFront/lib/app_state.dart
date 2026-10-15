import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'auth.dart';
import 'strings.dart';
import 'theme.dart';

enum OperatorAuthStatus {
  checking,
  authorized,
  notAnOperator,
  error,
  signedOut,
}

class AppState extends ChangeNotifier {
  final AdminApi api;
  final AuthService auth;

  OperatorAuthStatus _status = OperatorAuthStatus.checking;
  String? _statusError;
  String? _lastCheckedUid;
  StreamSubscription<OperatorUser?>? _authSub;

  OperatorAuthStatus get status => _status;
  String? get statusError => _statusError;
  OperatorUser? get currentUser => auth.currentUser;

  AppState({
    required this.api,
    required this.auth,
  }) {
    final user = auth.currentUser;
    if (user == null) {
      _status = OperatorAuthStatus.signedOut;
    } else {
      _lastCheckedUid = user.uid;
      checkOperatorStatus();
    }
    _init();
  }

  void _init() {
    _authSub = auth.authStateChanges.listen((user) {
      if (user == null) {
        _lastCheckedUid = null;
        _status = OperatorAuthStatus.signedOut;
        _statusError = null;
        notifyListeners();
      } else if (user.uid != _lastCheckedUid) {
        _lastCheckedUid = user.uid;
        checkOperatorStatus();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> checkOperatorStatus() async {
    _status = OperatorAuthStatus.checking;
    _statusError = null;
    notifyListeners();

    try {
      await api.get('/status');
      _status = OperatorAuthStatus.authorized;
      _statusError = null;
    } on AdminApiException catch (e) {
      if (e.code == 'adminOnly') {
        _status = OperatorAuthStatus.notAnOperator;
      } else {
        _status = OperatorAuthStatus.error;
        _statusError = Strings.errorFor(
          code: e.code,
          statusCode: e.statusCode,
          serverMessage: e.message,
        );
      }
    } catch (e) {
      _status = OperatorAuthStatus.error;
      _statusError = Strings.errGenericFallback;
    }
    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    await auth.signInWithGoogle();
  }

  Future<void> signInWithEmailPassword(String email, String password) async {
    await auth.signInWithEmailPassword(email, password);
  }

  Future<void> signOut() async {
    await auth.signOut();
  }

  /// Runs a mutating API call.
  /// If [AdminApiException] 401 `adminReauthRequired` is thrown:
  ///   - prompts the user with a re-authentication dialog
  ///   - on confirm: re-authenticates (popup for Google, credential for password),
  ///     force-refreshes the ID token, and retries the mutation ONCE.
  ///   - on cancel: change is aborted and user is notified.
  /// Shows success or error SnackBar. Returns true if mutation succeeded.
  Future<bool> runMutation(
    BuildContext context,
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    try {
      await action();
      if (context.mounted && successMessage != null) {
        _showSnackBar(context, successMessage, isError: false);
      }
      return true;
    } on AdminApiException catch (e) {
      if (e.statusCode == 401 && e.code == 'adminReauthRequired') {
        if (!context.mounted) return false;
        final confirmed = await _promptReauth(context);
        if (!confirmed) {
          if (context.mounted) {
            _showSnackBar(context, Strings.reauthCancelled, isError: true);
          }
          return false;
        }

        // Reauth confirmed: perform reauth and retry once
        try {
          final user = auth.currentUser;
          if (user != null && user.isGoogle) {
            await auth.reauthenticateWithGoogle();
          }
          await auth.getIdToken(forceRefresh: true);

          // Retry the action once
          await action();
          if (context.mounted && successMessage != null) {
            _showSnackBar(context, successMessage, isError: false);
          }
          return true;
        } catch (retryErr) {
          if (context.mounted) {
            final msg = retryErr is AdminApiException
                ? Strings.errorFor(
                    code: retryErr.code,
                    statusCode: retryErr.statusCode,
                    serverMessage: retryErr.message,
                  )
                : Strings.errGenericFallback;
            _showSnackBar(context, msg, isError: true);
          }
          return false;
        }
      } else {
        if (context.mounted) {
          final msg = Strings.errorFor(
            code: e.code,
            statusCode: e.statusCode,
            serverMessage: e.message,
          );
          _showSnackBar(context, msg, isError: true);
        }
        return false;
      }
    } catch (e) {
      if (context.mounted) {
        _showSnackBar(context, Strings.errGenericFallback, isError: true);
      }
      return false;
    }
  }

  Future<bool> _promptReauth(BuildContext context) async {
    final user = auth.currentUser;
    final isGoogle = user?.isGoogle ?? true;

    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ReauthDialog(
        auth: auth,
        isGoogle: isGoogle,
      ),
    );
    return res == true;
  }

  void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : AppColors.successInk,
      ),
    );
  }
}

class _ReauthDialog extends StatefulWidget {
  final AuthService auth;
  final bool isGoogle;

  const _ReauthDialog({
    required this.auth,
    required this.isGoogle,
  });

  @override
  State<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends State<_ReauthDialog> {
  final _passController = TextEditingController();
  String? _inlineError;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _passController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.isGoogle) {
      Navigator.of(context).pop(true);
      return;
    }
    final pass = _passController.text.trim();
    if (pass.isEmpty) return;

    setState(() {
      _isSubmitting = true;
      _inlineError = null;
    });

    try {
      await widget.auth.reauthenticateWithPassword(pass);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _inlineError = Strings.errWrongPasswordRetry;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Strings.reauthRequiredTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(Strings.reauthRequiredBody),
          if (!widget.isGoogle) ...[
            const SizedBox(height: 16),
            Text(Strings.reauthPasswordPrompt),
            const SizedBox(height: 8),
            TextField(
              controller: _passController,
              obscureText: true,
              enabled: !_isSubmitting,
              decoration: InputDecoration(
                labelText: Strings.passwordLabel,
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_inlineError != null) ...[
              const SizedBox(height: 8),
              Text(
                _inlineError!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: Text(Strings.cancel),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: Text(Strings.confirm),
        ),
      ],
    );
  }
}

