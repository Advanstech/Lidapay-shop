import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Primary CTA: magenta→violet gradient pill with soft glow.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final glowAlpha = Theme.of(context).brightness == Brightness.dark
        ? 0.45
        : 0.30;

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            if (enabled)
              BoxShadow(
                color: AppColors.primary.withValues(alpha: glowAlpha),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: loading ? null : onPressed,
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 56,
              width: double.infinity,
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            icon!,
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
