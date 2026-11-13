import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/auth_hero_header.dart';
import '../providers.dart';

/// POST /api/v1/users/confirm-reset-password — reached from the emailed
/// `/reset-password?token=…` link (deep link or web path). The token is the
/// only authority; no session is required.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _done = false;
  bool _tokenMissing = false;
  bool _linkRejected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tokenMissing = widget.token.trim().isEmpty;
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authSessionProvider.notifier)
          .confirmPasswordReset(
            token: widget.token.trim(),
            newPassword: _password.text,
          );
      if (mounted) setState(() => _done = true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          // Token rejected/expired — retrying the same link can't help.
          _linkRejected = e.message.toLowerCase().contains('token') ||
              e.message.toLowerCase().contains('expired') ||
              e.message.toLowerCase().contains('invalid');
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final invalidLink = _tokenMissing || _linkRejected;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthHeroHeader(
            height: 200,
            title: _done ? 'Password updated' : 'Choose a new password',
            subtitle: _done
                ? 'You can sign in with your new password.'
                : 'Pick a strong password for your LidaPay account.',
            onBack: () => context.canPop()
                ? context.pop()
                : context.go('/login'),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 20, 26, 32),
              child: _done
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: AppColors.success.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.success,
                                size: 30,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Your password has been reset. Sign in to continue.',
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontSize: 15.5,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        AppButton(
                          label: 'Back to sign in',
                          onPressed: () => context.go('/login'),
                        ),
                      ],
                    )
                  : invalidLink
                  ? _InvalidLink(
                      message: _tokenMissing
                          ? 'This reset link is missing its token. Request a '
                                'new reset link from the sign-in screen.'
                          : _error ??
                                'This reset link is invalid or has expired. '
                                'Request a new one from the sign-in screen.',
                    )
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 12),
                          AppTextField(
                            controller: _password,
                            label: 'New password',
                            hint: 'At least 6 characters',
                            prefixIcon: const Icon(
                              Icons.lock_outline_rounded,
                              size: 22,
                            ),
                            large: true,
                            obscureText: true,
                            validator: Validators.password,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 18),
                          AppTextField(
                            controller: _confirm,
                            label: 'Confirm new password',
                            hint: 'Repeat the new password',
                            prefixIcon: const Icon(
                              Icons.lock_outline_rounded,
                              size: 22,
                            ),
                            large: true,
                            obscureText: true,
                            validator: (v) =>
                                Validators.confirmPassword(v, _password.text),
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          if (_password.text.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _StrengthBar(password: _password.text),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: scheme.error,
                                fontSize: 14.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 28),
                          AppButton(
                            label: 'Update password',
                            loading: _loading,
                            onPressed: _submit,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvalidLink extends StatelessWidget {
  const _InvalidLink({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.link_off_rounded,
                color: AppColors.error,
                size: 30,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 15.5,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        AppButton(
          label: 'Request a new link',
          onPressed: () => context.go('/forgot-password'),
        ),
      ],
    );
  }
}

class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final strength = PasswordStrength.of(password);
    final (color, label) = switch (strength) {
      PasswordStrength.empty => (Colors.grey, ''),
      PasswordStrength.weak => (AppColors.error, 'Weak'),
      PasswordStrength.fair => (AppColors.warning, 'Fair'),
      PasswordStrength.good => (AppColors.success, 'Good'),
      PasswordStrength.strong => (AppColors.success, 'Strong'),
    };
    final score = switch (strength) {
      PasswordStrength.empty => 0,
      PasswordStrength.weak => 1,
      PasswordStrength.fair => 2,
      PasswordStrength.good => 3,
      PasswordStrength.strong => 4,
    };
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i < score ? color : color.withValues(alpha: 0.18),
              ),
            ),
          ),
        ],
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
