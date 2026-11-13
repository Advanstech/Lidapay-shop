import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The single card surface used across the app: large radius, soft ambient
/// shadow, hairline border in dark mode and an optional tap ripple.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
    this.radius = AppRadii.card,
    this.color,
    this.margin,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = BorderRadius.circular(radius);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: AppShadows.card(isDark),
      ),
      child: Material(
        color: color ?? scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: r,
          side: isDark
              ? const BorderSide(color: Colors.white10)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
