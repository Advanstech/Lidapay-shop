import 'package:flutter/material.dart';

class AmountPresetChip extends StatelessWidget {
  const AmountPresetChip({
    super.key,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final double value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.14)
              : scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? scheme.primary
                : (isDark ? Colors.white12 : const Color(0xFFECEAF4)),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Text(
          'GH₵ ${value.toStringAsFixed(0)}',
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected ? scheme.primary : scheme.onSurface,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
