import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sticky_header.dart';

/// Everything the app offers, one tap away — styled to match the Air Services
/// hub with hero stats, category pills, featured cards, and service tiles.
class ServicesScreen extends ConsumerStatefulWidget {
  const ServicesScreen({super.key});

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  String _selectedFilter = 'All';

  List<
    ({IconData icon, Color color, String title, String subtitle, String route})
  >
  get _filteredServices => switch (_selectedFilter) {
    'Airtime' => [
      (
        icon: Icons.phone_android_rounded,
        color: AppColors.primary,
        title: 'Buy Airtime',
        subtitle: 'Top up a Ghana mobile number',
        route: AppRoutes.airtime,
      ),
      (
        icon: Icons.public_rounded,
        color: AppColors.violet,
        title: 'Global Airtime',
        subtitle: 'Recharge international mobile numbers',
        route: AppRoutes.globalAirtime,
      ),
    ],
    'Data' => [
      (
        icon: Icons.wifi_rounded,
        color: AppColors.violet,
        title: 'Internet Data',
        subtitle: 'Ghana bundles and worldwide data top-ups',
        route: AppRoutes.data,
      ),
    ],
    'Convert' => [
      (
        icon: Icons.swap_horiz_rounded,
        color: AppColors.success,
        title: 'Lida Value',
        subtitle: 'Use, send, sell or convert your value',
        route: AppRoutes.lidaValue,
      ),
    ],
    'Others' => [
      (
        icon: Icons.qr_code_scanner_rounded,
        color: AppColors.primary,
        title: 'QR Pay',
        subtitle: 'Scan to pay',
        route: AppRoutes.qrPay,
      ),
      (
        icon: Icons.account_balance_rounded,
        color: AppColors.navy,
        title: 'GTPay',
        subtitle: 'Bank payment services',
        route: AppRoutes.gtPay,
      ),
      (
        icon: Icons.stars_rounded,
        color: AppColors.warning,
        title: 'Lida Points',
        subtitle: 'Earn and redeem loyalty rewards',
        route: AppRoutes.lidaPoints,
      ),
      (
        icon: Icons.card_giftcard_rounded,
        color: AppColors.primary,
        title: 'Invite & Earn',
        subtitle: 'Refer friends and earn bonuses',
        route: AppRoutes.inviteEarn,
      ),
      (
        icon: Icons.support_agent_rounded,
        color: AppColors.violet,
        title: 'Support',
        subtitle: 'Get help from our team',
        route: AppRoutes.support,
      ),
    ],
    _ => [],
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final topInset = MediaQuery.paddingOf(context).top;
    final scaffoldBg = isDark
        ? AppColors.darkScaffold
        : AppColors.lightScaffold;

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: StickySliverHeaderDelegate(
              height: topInset + 80,
              builder: (context, isStuck) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  boxShadow: isStuck
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, topInset + 12, 20, 12),
                  child: _AirServicesTopBar(
                    onBack: () => context.go(AppRoutes.home),
                    onSearch: () => context.push(AppRoutes.airtime),
                  ),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: _AirServicesHeroStats()),
          SliverPersistentHeader(
            pinned: true,
            delegate: StickySliverHeaderDelegate(
              height: 60,
              builder: (context, isStuck) => DecoratedBox(
                decoration: BoxDecoration(
                  color: scaffoldBg,
                  boxShadow: isStuck
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.26 : 0.06,
                            ),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _FilterPill(
                        icon: Icons.grid_view_rounded,
                        label: 'All',
                        selected: _selectedFilter == 'All',
                        onTap: () => setState(() => _selectedFilter = 'All'),
                      ),
                      const SizedBox(width: 10),
                      _FilterPill(
                        icon: Icons.phone_android_rounded,
                        label: 'Airtime',
                        selected: _selectedFilter == 'Airtime',
                        onTap: () =>
                            setState(() => _selectedFilter = 'Airtime'),
                      ),
                      const SizedBox(width: 10),
                      _FilterPill(
                        icon: Icons.wifi_rounded,
                        label: 'Data',
                        selected: _selectedFilter == 'Data',
                        onTap: () => setState(() => _selectedFilter = 'Data'),
                      ),
                      const SizedBox(width: 10),
                      _FilterPill(
                        icon: Icons.swap_horiz_rounded,
                        label: 'Convert',
                        selected: _selectedFilter == 'Convert',
                        onTap: () =>
                            setState(() => _selectedFilter = 'Convert'),
                      ),
                      const SizedBox(width: 10),
                      _FilterPill(
                        icon: Icons.more_horiz_rounded,
                        label: 'Others',
                        selected: _selectedFilter == 'Others',
                        onTap: () => setState(() => _selectedFilter = 'Others'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selectedFilter == 'All') ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                    child: Row(
                      children: [
                        Text(
                          'Featured Services',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            'Popular',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: _FeaturedServiceCard(
                            icon: Icons.signal_cellular_alt_rounded,
                            badge: 'Popular',
                            title: 'Buy Airtime',
                            subtitle: 'Instant top-up\nworldwide',
                            gradient: AppColors.brandGradient,
                            shadowColor: AppColors.primary,
                            onTap: () => context.push(AppRoutes.airtime),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _FeaturedServiceCard(
                            icon: Icons.wifi_rounded,
                            title: 'Data Bundles',
                            subtitle: 'High-speed\ninternet',
                            gradient: AppColors.heroGradient,
                            shadowColor: AppColors.navy,
                            onTap: () => context.push(AppRoutes.data),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    child: Text(
                      'Quick Actions',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                  ),
                  SizedBox(
                    height: 92,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _QuickActionPill(
                          icon: Icons.public_rounded,
                          label: 'Global Airtime',
                          color: AppColors.violet,
                          onTap: () => context.push(AppRoutes.globalAirtime),
                        ),
                        const SizedBox(width: 12),
                        _QuickActionPill(
                          icon: Icons.qr_code_scanner_rounded,
                          label: 'QR Pay',
                          color: AppColors.primary,
                          onTap: () => context.push(AppRoutes.qrPay),
                        ),
                        const SizedBox(width: 12),
                        _QuickActionPill(
                          icon: Icons.account_balance_rounded,
                          label: 'GTPay',
                          color: AppColors.navy,
                          onTap: () => context.push(AppRoutes.gtPay),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_selectedFilter != 'All')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_selectedFilter services',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Choose a service to get started',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        for (final service in _filteredServices) ...[
                          _ServiceRowCard(
                            icon: service.icon,
                            iconBg: service.color,
                            title: service.title,
                            subtitle: service.subtitle,
                            isDark: isDark,
                            onTap: () => context.push(service.route),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ],
                    ),
                  ),
                if (_selectedFilter == 'All')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'All Services',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Convert & Transfer',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ServiceRowCard(
                          icon: Icons.local_offer_rounded,
                          iconBg: const Color(0xFF07A56B),
                          title: 'Lida Value',
                          titleSuffix: 'Buyback',
                          badgeText: 'NEW',
                          subtitle:
                              'Sell Lida Value, get discounted cash or crypto',
                          isDark: isDark,
                          onTap: () => context.push(AppRoutes.lidaValue),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Rewards & Support',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ServiceRowCard(
                          icon: Icons.stars_rounded,
                          iconBg: AppColors.warning,
                          title: 'Lida Points',
                          subtitle: 'Earn and redeem loyalty rewards',
                          isDark: isDark,
                          onTap: () => context.push(AppRoutes.lidaPoints),
                        ),
                        const SizedBox(height: 14),
                        _ServiceRowCard(
                          icon: Icons.card_giftcard_rounded,
                          iconBg: AppColors.primary,
                          title: 'Invite & Earn',
                          subtitle: 'Refer friends and earn instant bonuses',
                          isDark: isDark,
                          onTap: () => context.push(AppRoutes.inviteEarn),
                        ),
                        const SizedBox(height: 14),
                        _ServiceRowCard(
                          icon: Icons.support_agent_rounded,
                          iconBg: AppColors.violet,
                          title: 'Support',
                          subtitle: 'Get 24/7 assistance from our team',
                          isDark: isDark,
                          onTap: () => context.push(AppRoutes.support),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AirServicesTopBar extends StatelessWidget {
  const _AirServicesTopBar({required this.onBack, required this.onSearch});

  final VoidCallback onBack;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _HeroIconButton(icon: Icons.arrow_back_rounded, onTap: onBack),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Air Services',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Airtime • Data • Convert',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Opacity(
                opacity: 0,
                child: SizedBox(
                  height: 1,
                  child: Text(
                    'All services, one wallet',
                    style: TextStyle(fontSize: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
        _HeroIconButton(icon: Icons.search_rounded, onTap: onSearch),
      ],
    );
  }
}

class _AirServicesHeroStats extends StatelessWidget {
  const _AirServicesHeroStats();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      child: const Row(
        children: [
          Expanded(
            child: _HeroStatChip(
              icon: Icons.bolt_rounded,
              title: 'Instant',
              subtitle: 'Delivery',
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: _HeroStatChip(
              icon: Icons.public_rounded,
              title: '150+',
              subtitle: 'Countries',
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: _HeroStatChip(
              icon: Icons.verified_user_rounded,
              title: 'Secure',
              subtitle: 'Payments',
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _HeroStatChip extends StatelessWidget {
  const _HeroStatChip({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.76),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
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
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : (isDark ? AppColors.darkSurface : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isDark ? Colors.white12 : const Color(0xFFE6E4EC)),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : scheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedServiceCard extends StatelessWidget {
  const _FeaturedServiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.shadowColor,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final LinearGradient gradient;
  final Color shadowColor;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 204,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: shadowColor.withValues(alpha: 0.28),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const Spacer(),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'Get Started',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: shadowColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionPill extends StatelessWidget {
  const _QuickActionPill({
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 112,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceRowCard extends StatelessWidget {
  const _ServiceRowCard({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
    this.titleSuffix,
    this.badgeText,
  });

  final IconData icon;
  final Color iconBg;
  final String title;
  final String? titleSuffix;
  final String? badgeText;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: iconBg.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurface,
                              ),
                            ),
                            if (titleSuffix != null)
                              Text(
                                titleSuffix!,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurface,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (badgeText != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: iconBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            badgeText!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBg.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.arrow_forward_rounded, color: iconBg, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
