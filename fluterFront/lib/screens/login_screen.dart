import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Login: centered card, email+password, Google button.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isRegistering = false;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final app = context.read<AppState>();
    if (_email.text.isEmpty || _password.text.isEmpty) {
      app.setError(AppLocalizations.of(context).errEmailPasswordRequired);
      return;
    }
    setState(() => _loading = true);
    try {
      if (_isRegistering) {
        await app.register(_email.text.trim(), _password.text);
      } else {
        await app.login(_email.text.trim(), _password.text);
      }
      // Let the OS password manager offer to save the credentials.
      TextInput.finishAutofillContext();
    } catch (_) {
      // errors are surfaced via the state toasts
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    final ctl = TextEditingController(text: _email.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text(l.resetPasswordTitle,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: VInput(
            controller: ctl,
            label: l.emailLabel,
            placeholder: 'hello@carecoins.app',
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.sendResetEmail)),
        ],
      ),
    );
    if (ok == true && ctl.text.trim().isNotEmpty) {
      await app.resetPassword(ctl.text);
    }
    ctl.dispose();
  }

  Future<void> _google() async {
    try {
      await context.read<AppState>().loginWithGoogle();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 64),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: VCard(
              title: _isRegistering
                  ? l.createAccountTitle
                  : l.welcomeCardTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isRegistering ? l.signUpIntro : l.signInIntro,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textSecondary, height: 1.6),
                  ),
                  const SizedBox(height: 32),
                  AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        VInput(
                            controller: _email,
                            label: l.emailLabel,
                            placeholder: 'hello@carecoins.app',
                            enabled: !_loading,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [
                              AutofillHints.username,
                              AutofillHints.email
                            ],
                            textInputAction: TextInputAction.next),
                        const SizedBox(height: 16),
                        VInput(
                            controller: _password,
                            label: l.passwordLabel,
                            placeholder: '••••••••',
                            obscure: true,
                            enabled: !_loading,
                            autofillHints: [
                              _isRegistering
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password
                            ],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit()),
                      ],
                    ),
                  ),
                  if (!_isRegistering)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _loading ? null : _forgotPassword,
                        child: Text(l.forgotPassword,
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                decoration: TextDecoration.underline)),
                      ),
                    ),
                  const SizedBox(height: 24),
                  VButton(
                    block: true,
                    disabled: _loading,
                    onPressed: _submit,
                    child: Text(_loading
                        ? l.processing
                        : (_isRegistering ? l.signUp : l.signIn)),
                  ),
                  const SizedBox(height: 24),
                  Row(children: [
                    const Expanded(child: Divider(color: AppColors.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      child: Text(l.orDivider,
                          style: const TextStyle(
                              fontSize: 13.6, color: AppColors.textSecondary)),
                    ),
                    const Expanded(child: Divider(color: AppColors.border)),
                  ]),
                  const SizedBox(height: 24),
                  VButton(
                    type: VButtonType.secondary,
                    block: true,
                    onPressed: _google,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _GoogleMark(),
                        const SizedBox(width: 10),
                        Text(l.signInWithGoogle),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                          _isRegistering
                              ? l.alreadyHaveAccount
                              : l.newToCareCoins,
                          style: const TextStyle(
                              fontSize: 14.4, color: AppColors.textSecondary)),
                      TextButton(
                        onPressed: () =>
                            setState(() => _isRegistering = !_isRegistering),
                        child: Text(
                            _isRegistering
                                ? l.signInInstead
                                : l.createAnAccount,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    // Simple multicolour "G" mark stand-in for the inline SVG.
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            Color(0xFF4285F4),
            Color(0xFF34A853),
            Color(0xFFFBBC05),
            Color(0xFFEA4335),
            Color(0xFF4285F4),
          ],
        ),
      ),
      child: const Text('G',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
    );
  }
}
