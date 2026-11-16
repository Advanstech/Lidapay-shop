import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Evaluates the five password policy rules enforced by the hosted LidaPay
/// reset form alongside live engagement and completion flags.
@immutable
class PasswordRuleEvaluation {
  const PasswordRuleEvaluation({
    required this.minLength,
    required this.mixedCase,
    required this.hasNumber,
    required this.hasSymbol,
    required this.passwordsMatch,
    required this.engaged,
  });

  factory PasswordRuleEvaluation.evaluate(
    String password, [
    String confirmPassword = '',
  ]) {
    return PasswordRuleEvaluation(
      minLength: password.length >= 8,
      mixedCase:
          RegExp(r'[A-Z]').hasMatch(password) &&
          RegExp(r'[a-z]').hasMatch(password),
      hasNumber: RegExp(r'\d').hasMatch(password),
      hasSymbol: RegExp(r'[^A-Za-z0-9]').hasMatch(password),
      passwordsMatch: password.isNotEmpty && password == confirmPassword,
      engaged: password.isNotEmpty || confirmPassword.isNotEmpty,
    );
  }

  final bool minLength;
  final bool mixedCase;
  final bool hasNumber;
  final bool hasSymbol;
  final bool passwordsMatch;
  final bool engaged;

  bool get allMet =>
      minLength && mixedCase && hasNumber && hasSymbol && passwordsMatch;

  int get passwordRuleCount =>
      (minLength ? 1 : 0) +
      (mixedCase ? 1 : 0) +
      (hasNumber ? 1 : 0) +
      (hasSymbol ? 1 : 0);

  List<(String, bool)> get rules => [
    ('At least 8 characters', minLength),
    ('Uppercase & lowercase letters', mixedCase),
    ('At least one number', hasNumber),
    ('At least one symbol (!@#\$, etc.)', hasSymbol),
    ('Passwords match', passwordsMatch),
  ];
}

/// Calm-until-typing password requirements checklist rendered *above* password
/// inputs so mobile keyboards and autofill toolbars do not cover it.
class PasswordRequirementsPanel extends StatelessWidget {
  const PasswordRequirementsPanel({
    super.key,
    required this.password,
    required this.confirmPassword,
  });

  final String password;
  final String confirmPassword;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final eval = PasswordRuleEvaluation.evaluate(password, confirmPassword);
    final engaged = eval.engaged;
    final allMet = eval.allMet;

    final int filledBars;
    final Color tierColor;
    final String statusLabel;

    if (!engaged) {
      filledBars = 0;
      tierColor = scheme.outlineVariant;
      statusLabel = 'Not started';
    } else if (allMet) {
      filledBars = 4;
      tierColor = AppColors.success;
      statusLabel = 'Strong — ready to save';
    } else {
      final count = eval.passwordRuleCount;
      if (count <= 1) {
        filledBars = 1;
        tierColor = AppColors.warning;
        statusLabel = 'Weak';
      } else if (count == 2) {
        filledBars = 2;
        tierColor = AppColors.warning;
        statusLabel = 'Fair';
      } else if (count == 3) {
        filledBars = 3;
        tierColor = AppColors.success;
        statusLabel = 'Good';
      } else {
        filledBars = 3;
        tierColor = AppColors.success;
        statusLabel = 'Confirm password';
      }
    }

    final panelColor = allMet
        ? AppColors.success.withValues(alpha: 0.08)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.35);
    final borderColor = allMet
        ? AppColors.success.withValues(alpha: 0.5)
        : scheme.outlineVariant.withValues(alpha: 0.55);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: allMet ? 1.4 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Password requirements',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: !engaged
                      ? scheme.surfaceContainerHighest.withValues(alpha: 0.7)
                      : tierColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: !engaged ? scheme.onSurfaceVariant : tierColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 5,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: i < filledBars
                          ? tierColor
                          : scheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          for (final (label, met) in eval.rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    met && engaged
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 16,
                    color: met && engaged
                        ? AppColors.success
                        : scheme.onSurfaceVariant.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: met && engaged
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: met && engaged
                            ? AppColors.success
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
