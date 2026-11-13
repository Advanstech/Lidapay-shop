import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Wide visual card for horizontal rails. Set [dark] for the premium ink
/// variant (used by Lida Value) — ink gradient with a gold accent.
class RailCard extends StatefulWidget {
  const RailCard({
    super.key,
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
    this.caption,
    this.dark = false,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;
  final String? caption;
  final bool dark;

  @override
  State<RailCard> createState() => _RailCardState();
}

class _RailCardState extends State<RailCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isInk = widget.dark;
    final labelColor = isInk ? Colors.white : scheme.onSurface;
    final captionColor = isInk ? Colors.white70 : scheme.onSurfaceVariant;
    final iconColor = widget.tint == AppColors.gold
        ? AppColors.ink
        : Colors.white;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Container(
          width: 146,
          height: 128,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: isInk
                ? AppColors.heroGradient
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.tint.withValues(alpha: 0.16),
                      widget.tint.withValues(alpha: 0.03),
                    ],
                  ),
            borderRadius: BorderRadius.circular(AppRadii.card - 4),
            border: Border.all(
              color: isInk
                  ? Colors.white.withValues(alpha: 0.12)
                  : widget.tint.withValues(alpha: 0.16),
            ),
            boxShadow: AppShadows.card(isDark),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: widget.tint,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.glow(
                    widget.tint,
                    alpha: isInk ? 0.45 : 0.3,
                    blur: 16,
                  ),
                ),
                child: Icon(widget.icon, color: iconColor, size: 21),
              ),
              const Spacer(),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: labelColor,
                ),
              ),
              if (widget.caption != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: captionColor),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
