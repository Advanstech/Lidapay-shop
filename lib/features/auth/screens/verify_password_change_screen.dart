import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/auth_hero_header.dart';
import '../providers.dart';

/// POST /api/v1/users/confirm-password-change — reached from the
/// `/verify-password-change?token=…` link the backend emails after a
/// signed-in password change. Confirms automatically on open; no session
/// is required because the token is the authority.
class VerifyPasswordChangeScreen extends ConsumerStatefulWidget {
  const VerifyPasswordChangeScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<VerifyPasswordChangeScreen> createState() =>
      _VerifyPasswordChangeScreenState();
}

class _VerifyPasswordChangeScreenState
    extends ConsumerState<VerifyPasswordChangeScreen> {
  bool _loading = true;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _confirm();
  }

  Future<void> _confirm() async {
    final token = widget.token.trim();
    if (token.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This verification link is missing its token.';
      });
      return;
    }
    try {
      await ref
          .read(authSessionProvider.notifier)
          .confirmPasswordChange(token: token);
      if (mounted) {
        setState(() {
          _loading = false;
          _done = true;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Could not confirm the change. Check your connection and '
              'try the link again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _done
        ? 'Password changed'
        : _error != null
        ? 'Link problem'
        : 'Confirming…';
    final subtitle = _done
        ? 'Your new password is active — sign in with it next time.'
        : _error ?? 'Verifying your password change…';

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthHeroHeader(
            height: 200,
            title: title,
            subtitle: subtitle,
            onBack: () => context.canPop()
                ? context.pop()
                : context.go('/home'),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 20, 26, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: (_done ? AppColors.success : AppColors.error)
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: (_done
                                  ? AppColors.success
                                  : AppColors.error)
                              .withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _done
                                ? Icons.check_circle_rounded
                                : Icons.link_off_rounded,
                            color: _done
                                ? AppColors.success
                                : AppColors.error,
                            size: 30,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              _done
                                  ? 'Password change confirmed. If you did '
                                        'not request this, sign in and '
                                        'change it again right away.'
                                  : (_error ??
                                        'This link could not be used. '
                                        'Request a new password change '
                                        'from your profile.'),
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
                    label: _done ? 'Done' : 'Back to profile',
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/home');
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
