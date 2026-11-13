import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Filled icon tile used in the service grids — icon, tinted rounded square
/// and label with a press-scale effect.
class ActionTile extends StatefulWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  State<ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<ActionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.tint.withValues(alpha: 0.18),
                    widget.tint.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(AppRadii.tile - 2),
                border: Border.all(color: widget.tint.withValues(alpha: 0.18)),
              ),
              child: Icon(widget.icon, color: widget.tint, size: 23),
            ),
            const SizedBox(height: 7),
            Text(
              widget.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
                height: 1.15,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
