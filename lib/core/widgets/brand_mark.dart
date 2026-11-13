import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Official LidaPay brand mark used across splash, onboarding and auth.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 64,
    this.radius,
    this.fontSize,
    this.useDark = false,
  });

  final double size;
  final double? radius;
  final double? fontSize;
  final bool useDark;

  @override
  Widget build(BuildContext context) {
    final assetPath = useDark
        ? 'assets/images/app_logo_dark.png'
        : 'assets/images/app_logo.png';

    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        assetPath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(radius ?? size * 0.3),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: size * 0.45,
                offset: Offset(0, size * 0.14),
              ),
            ],
          ),
          child: Text(
            'L',
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              color: Colors.white,
              fontSize: fontSize ?? size * 0.52,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
