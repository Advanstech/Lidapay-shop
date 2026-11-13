import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

/// Bottom navigation hosting the five top-level tabs behind a floating,
/// frosted dock with an elevated gradient action in the centre.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final isShopBranch = navigationShell.currentIndex == 2;
    return Scaffold(
      extendBody: !isShopBranch,
      body: navigationShell,
      bottomNavigationBar: isShopBranch
          ? null
          : MainDock(
              selectedIndex: navigationShell.currentIndex,
              onSelect: (index) => navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              ),
            ),
    );
  }
}

/// The floating dock itself — public so tests can scope taps to it.
class MainDock extends StatelessWidget {
  const MainDock({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  static const _tabs = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Services'),
    (Icons.shopping_bag_outlined, Icons.shopping_bag_rounded, 'Shop'),
    (Icons.access_time_rounded, Icons.watch_later_rounded, 'History'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurface.withValues(alpha: 0.72)
                    : Colors.white.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : AppColors.navy.withValues(alpha: 0.06),
                ),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    Expanded(
                      flex: selectedIndex == i ? 2 : 1,
                      child: _DockTab(
                        icon: selectedIndex == i ? _tabs[i].$2 : _tabs[i].$1,
                        label: _tabs[i].$3,
                        selected: selectedIndex == i,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onSelect(i);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockTab extends StatelessWidget {
  const _DockTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDark ? Colors.white54 : const Color(0xFF9B9B9B);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: selected ? AppColors.brandGradient : null,
              borderRadius: BorderRadius.circular(28),
              boxShadow: selected
                  ? AppShadows.glow(AppColors.primary, alpha: 0.28, blur: 18)
                  : null,
            ),
            child: Center(
              child: selected
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: Colors.white, size: 24),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(icon, color: inactiveColor, size: 24),
                        Opacity(opacity: 0, child: Text(label)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
