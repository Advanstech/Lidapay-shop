import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../data/dashboard_models.dart';
import '../providers.dart';

/// Hero wallet card — deep-ink gradient with warm brand glows, the balance,
/// and live statistics tiles that route to their respective screens.
class WalletCard extends ConsumerWidget {
  const WalletCard({super.key, required this.wallet});

  final WalletSummary wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(balanceHiddenProvider);
    final transactions =
        ref.watch(recentTransactionsProvider).valueOrNull ??
        const <Transaction>[];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    double totalVolume = 0;
    for (final t in transactions) {
      totalVolume += t.amount;
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: AppShadows.glow(
          AppColors.primary,
          alpha: isDark ? 0.28 : 0.22,
          blur: 34,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.heroGradient),
              ),
            ),
            Positioned(
              top: -70,
              right: -50,
              child: _Glow(
                size: 220,
                color: Colors.white.withValues(alpha: 0.16),
              ),
            ),
            Positioned(
              bottom: -90,
              left: -70,
              child: _Glow(
                size: 260,
                color: AppColors.primary.withValues(alpha: 0.35),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push(AppRoutes.lidaValue),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'AVAILABLE LIDA VALUE',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white70,
                              size: 16,
                            ),
                            const Spacer(),
                            Semantics(
                              button: true,
                              label: hidden ? 'Show balance' : 'Hide balance',
                              child: GestureDetector(
                                onTap: () =>
                                    ref
                                            .read(
                                              balanceHiddenProvider.notifier,
                                            )
                                            .state =
                                        !hidden,
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.14,
                                      ),
                                    ),
                                  ),
                                  child: Icon(
                                    hidden
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            hidden
                                ? '•••••• LV'
                                : '${wallet.lidaValueUnits.toStringAsFixed(2)} LV',
                            key: ValueKey(hidden),
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.0,
                                ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Lida Value for airtime & data, sending, selling or converting',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Divider(
                    color: Colors.white.withValues(alpha: 0.14),
                    height: 1,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _HeroStatTile(
                          icon: Icons.stars_rounded,
                          iconColor: AppColors.warning,
                          value: hidden ? '•••' : '${wallet.lidaPoints}',
                          label: 'Points',
                          onTap: () => context.push(AppRoutes.lidaPoints),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _HeroStatTile(
                          icon: Icons.swap_horiz_rounded,
                          iconColor: const Color(0xFF4CD97B),
                          value: '${transactions.length}',
                          label: 'Transactions',
                          onTap: () => context.go(AppRoutes.history),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _HeroStatTile(
                          icon: Icons.analytics_rounded,
                          iconColor: const Color(0xFFFF86BA),
                          value: hidden
                              ? '•••'
                              : Formatters.compact(totalVolume.round()),
                          label: 'Analytics',
                          onTap: () => context.push(AppRoutes.historyAnalytics),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

class _HeroStatTile extends StatelessWidget {
  const _HeroStatTile({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 70,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: iconColor),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
