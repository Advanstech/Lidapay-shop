import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'country_flag_badge.dart';

/// Step bar shared by the Airtime and Internet Data wizards.
///
/// Both flows run the same five steps — `Country → Network → Phone →`
/// amount/bundle `→ review` — mirroring the legacy app's progress indicator.
/// The last two labels are configurable because the purchase step is an
/// amount for airtime and a bundle for data, and the review step has always
/// read differently between the two.
class ServiceWizardStepBar extends StatelessWidget {
  const ServiceWizardStepBar({
    super.key,
    required this.currentStep,
    required this.onStepTap,
    this.purchaseLabel = 'Amount',
    this.reviewLabel = 'Review',
  });

  final int currentStep;
  final ValueChanged<int> onStepTap;
  final String purchaseLabel;
  final String reviewLabel;

  static const int stepCount = 5;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final labels = <String>[
      'Country',
      'Network',
      'Phone',
      purchaseLabel,
      reviewLabel,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      color: isDark ? AppColors.darkScaffold : AppColors.lightScaffold,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onStepTap(i + 1),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: (i + 1) <= currentStep
                            ? AppColors.brandGradient
                            : null,
                        color: (i + 1) <= currentStep
                            ? null
                            : (isDark ? AppColors.darkSurface : Colors.white),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: (i + 1) <= currentStep
                              ? AppColors.primary
                              : (isDark
                                    ? Colors.white24
                                    : const Color(0xFFD9D7E0)),
                          width: 1.5,
                        ),
                        boxShadow: (i + 1) == currentStep
                            ? AppShadows.glow(
                                AppColors.primary,
                                alpha: 0.32,
                                blur: 12,
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: (i + 1) < currentStep ||
                              currentStep == ServiceWizardStepBar.stepCount
                          ? const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: Colors.white,
                            )
                          : Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: (i + 1) == currentStep
                                    ? Colors.white
                                    : scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: (i + 1) == currentStep
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: (i + 1) == currentStep
                            ? AppColors.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i < labels.length - 1)
              Container(
                width: 12,
                height: 2.5,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: (i + 1) < currentStep
                      ? AppColors.primary
                      : (isDark ? Colors.white12 : const Color(0xFFE0DEE8)),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// PREVIOUS / NEXT (pay on the final step) bar used by both wizards.
class ServiceWizardBottomBar extends StatelessWidget {
  const ServiceWizardBottomBar({
    super.key,
    required this.isFinalStep,
    required this.confirmLabel,
    required this.canNext,
    required this.submitting,
    required this.onPrevious,
    required this.onNext,
  });

  final bool isFinalStep;
  final String confirmLabel;
  final bool canNext;
  final bool submitting;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.paddingOf(context).bottom + 14,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onPrevious,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.7),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'PREVIOUS',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: canNext ? onNext : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 48,
                decoration: BoxDecoration(
                  gradient: canNext ? AppColors.brandGradient : null,
                  color: canNext
                      ? null
                      : (isDark
                            ? AppColors.darkInput
                            : const Color(0xFFE5E5EA)),
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isFinalStep
                                ? Icons.lock_outline_rounded
                                : Icons.arrow_forward_rounded,
                            size: 17,
                            color: canNext
                                ? Colors.white
                                : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isFinalStep ? confirmLabel : 'NEXT',
                            style: TextStyle(
                              color: canNext
                                  ? Colors.white
                                  : scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              letterSpacing: 0.4,
                            ),
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

/// One selectable entry on the Network step.
class NetworkStepOption {
  const NetworkStepOption({
    required this.id,
    required this.label,
    this.subtitle,
    this.icon,
    this.logoName,
    this.logoUrl,
  });

  final String id;
  final String label;
  final String? subtitle;

  /// Glyph shown in the leading badge when the option has no operator logo.
  final IconData? icon;

  /// Operator name/logo for catalogue entries (rendered as a round badge).
  final String? logoName;
  final String? logoUrl;
}

/// The Network step body shared by both wizards: the destination's operator
/// list with the current pick highlighted.
///
/// The list is always allowed to be short or empty — [footer] carries the
/// "matched from the number" fallback note — because a catalogue outage must
/// never strand the wizard behind a step the user cannot complete.
class ServiceNetworkStep extends StatelessWidget {
  const ServiceNetworkStep({
    super.key,
    required this.intro,
    required this.options,
    required this.selectedId,
    required this.onSelected,
    this.footer,
    this.detecting = false,
  });

  final String intro;
  final List<NetworkStepOption> options;
  final String? selectedId;
  final ValueChanged<NetworkStepOption> onSelected;
  final Widget? footer;
  final bool detecting;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final cardBg = isDark ? AppColors.darkSurface : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          intro,
          style: TextStyle(
            fontSize: 15,
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        if (detecting) ...[
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              const SizedBox(width: 10),
              Text(
                'Matching a network from the number…',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        for (final option in options) ...[
          _NetworkTile(
            option: option,
            selected: option.id == selectedId,
            isDark: isDark,
            cardBg: cardBg,
            onTap: () => onSelected(option),
          ),
          const SizedBox(height: 12),
        ],
        if (footer != null) ...[footer!, const SizedBox(height: 4)],
      ],
    );
  }
}

class _NetworkTile extends StatelessWidget {
  const _NetworkTile({
    required this.option,
    required this.selected,
    required this.isDark,
    required this.cardBg,
    required this.onTap,
  });

  final NetworkStepOption option;
  final bool selected;
  final bool isDark;
  final Color cardBg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = selected
        ? AppColors.primary
        : (isDark ? Colors.white24 : const Color(0xFFEDEBF2));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.07) : cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isDark ? Colors.white10 : const Color(0xFFECEAF2)),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            if (option.logoName != null)
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 1.5),
                ),
                child: OperatorLogoBadge(
                  name: option.logoName!,
                  logoUrl: option.logoUrl,
                  size: 36,
                ),
              )
            else
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : (isDark ? AppColors.darkInput : const Color(0xFFF3F3F6)),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  option.icon ?? Icons.cell_tower_rounded,
                  size: 21,
                  color: selected ? AppColors.primary : scheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? AppColors.primary : scheme.onSurface,
                    ),
                  ),
                  if (option.subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      option.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
              size: 20,
              color: selected
                  ? AppColors.primary
                  : (isDark ? Colors.white30 : const Color(0xFFB9B6C4)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact "Network · MTN Ghana · Change" strip shown on the phone step of
/// both wizards, so the pick made on the Network step stays visible and
/// correctable without going back.
class NetworkSummaryRow extends StatelessWidget {
  const NetworkSummaryRow({
    super.key,
    required this.label,
    required this.onChange,
    this.pending = false,
  });

  final String label;
  final VoidCallback onChange;

  /// True while the operator is still being resolved from the number.
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkInput : const Color(0xFFF6F6F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.cell_tower_rounded, size: 17, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
          if (pending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: onChange,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Change'),
            ),
        ],
      ),
    );
  }
}
