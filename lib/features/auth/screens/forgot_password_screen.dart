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

/// POST /api/v1/users/reset-password — mock just simulates the email.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
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
          .requestPasswordReset(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthHeroHeader(
            height: 220,
            title: 'Reset password',
            subtitle: _sent
                ? 'Check your email or messages'
                : 'We\'ll send you a secure reset link.',
            onBack: () => context.pop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 20, 26, 32),
              child: _sent
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
                                Icons.mark_email_read_outlined,
                                color: AppColors.success,
                                size: 30,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'If an account exists for ${_email.text.trim()}, a reset link is on its way. Open it to choose a new password.',
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
                          onPressed: () => context.pop(),
                        ),
                      ],
                    )
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 12),
                          AppTextField(
                            controller: _email,
                            label: 'Email or phone number',
                            hint: 'you@example.com or 0244588584',
                            prefixIcon: const Icon(
                              Icons.alternate_email_rounded,
                              size: 22,
                            ),
                            large: true,
                            validator: Validators.emailOrPhone,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                          ),
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
                            label: 'Send reset link',
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
