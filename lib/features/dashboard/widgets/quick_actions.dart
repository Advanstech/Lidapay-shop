import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Horizontal icon-forward quick actions on the dashboard.
class QuickActions extends StatelessWidget {
  const QuickActions({super.key});

  static const _actions = [
    (icon: Icons.send_rounded, label: 'Send Airtime', color: Color(0xFFE31C5F)),
    (
      icon: Icons.wifi_tethering_rounded,
      label: 'Buy Data',
      color: Color(0xFF2A2550),
    ),
    (
      icon: Icons.storefront_rounded,
      label: 'Visit Shop',
      color: Color(0xFF1FA97A),
    ),
    (
      icon: Icons.diamond_outlined,
      label: 'Lida Value',
      color: Color(0xFFF6C453),
    ),
    (icon: Icons.add_card_rounded, label: 'Top Up', color: Color(0xFF6C5CE7)),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final action = _actions[i];
          return _QuickAction(
            icon: action.icon,
            label: action.label,
            color: action.color,
            onTap: () {
              HapticFeedback.selectionClick();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${action.label} — coming in the next milestone.',
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _QuickAction extends StatefulWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1,
        duration: const Duration(milliseconds: 120),
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(widget.icon, color: widget.color),
              ),
              const SizedBox(height: 8),
              Text(
                widget.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
