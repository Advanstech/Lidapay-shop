import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/sticky_header.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/providers.dart';
import '../../dashboard/data/dashboard_models.dart';
import '../../dashboard/providers.dart';
import '../../legal/legal_content.dart';
import '../../legal/policy_acceptance.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isPreparingDeletionRequest = false;

  @override
  void initState() {
    super.initState();
    // Fresh balances every time the tab is (re)built — the wallet summary
    // is a plain FutureProvider and would otherwise serve cached numbers.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(walletSummaryProvider);
      ref.invalidate(profileSyncProvider);
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(walletSummaryProvider);
    ref.invalidate(profileSyncProvider);
    try {
      await ref.read(walletSummaryProvider.future);
    } catch (_) {
      // The wallet section surfaces its own error state.
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text(
          'Are you sure you want to log out of your Lidapay account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(authSessionProvider.notifier).logout();
      if (mounted) context.go(AppRoutes.login);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('Delete Account?'),
          ],
        ),
        content: const Text(
          'This opens an email request to Advansis support. Send the email '
          'to request account and personal-data deletion; support may verify '
          'account ownership before completing it. Some transaction records '
          'may be retained where the law requires. Withdraw or spend any '
          'remaining wallet balance first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Open email'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _isPreparingDeletionRequest) return;

    setState(() => _isPreparingDeletionRequest = true);
    try {
      final user = ref.read(authSessionProvider)?.user;
      final launched = await launchUrl(
        accountDeletionRequestUri(
          email: user?.email ?? '',
          phoneNumber: user?.phoneNumber ?? '',
        ),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            launched
                ? 'Email app opened. Send the message to submit your request.'
                : 'Could not open email. Contact $supportEmail to request account deletion.',
          ),
        ),
      );
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open email. Contact info@advansistechnologies.com to request account deletion.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isPreparingDeletionRequest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pulls GET /users/profile once per mount; fresh fields fold into the
    // session when it resolves.
    ref.watch(profileSyncProvider);
    final user = ref.watch(authSessionProvider)?.user;
    final wallet = ref.watch(walletSummaryProvider);
    final themeMode = ref.watch(themeModeProvider);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: topInset + 76,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: StickySliverHeaderDelegate(
                height: topInset + 70,
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
                    padding: EdgeInsets.fromLTRB(20, topInset + 10, 20, 10),
                    child: _ProfileTopBar(
                      onBack: () => context.go(AppRoutes.home),
                      onEdit: () => context.push(AppRoutes.editProfile),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _ProfileBrandHero(
                user: user,
                wallet: wallet,
                onEdit: () => context.push(AppRoutes.editProfile),
                onTapPoints: () => context.push(AppRoutes.lidaPoints),
                onTapValue: () => context.push(AppRoutes.lidaValue),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 22)),
            const SliverToBoxAdapter(child: _SectionTitle('Appearance')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _ThemeModeCard(
                  themeMode: themeMode,
                  isDark: isDark,
                  onChanged: (mode) =>
                      ref.read(themeModeProvider.notifier).set(mode),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            const SliverToBoxAdapter(child: _SectionTitle('Account')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _KycProgressCard(user: user),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: _BrandActionTile(
                icon: Icons.verified_user_rounded,
                iconGradient: AppColors.brandGradient,
                label: 'Profile & KYC',
                subtitle: 'Update details and verify contacts',
                badge: user?.isVerified == true ? 'VERIFIED' : 'ACTION',
                badgeColor: user?.isVerified == true
                    ? AppColors.success
                    : AppColors.primary,
                onTap: () => context.push(AppRoutes.editProfile),
              ),
            ),
            SliverToBoxAdapter(
              child: _BrandActionTile(
                icon: Icons.lock_reset_rounded,
                iconGradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFB7185), Color(0xFFE11D48)],
                ),
                label: 'Change password',
                subtitle: 'Update your password via email verification',
                onTap: () => context.push(AppRoutes.changePassword),
              ),
            ),
            SliverToBoxAdapter(
              child: _BrandActionTile(
                icon: Icons.diamond_rounded,
                iconGradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF9327F0), Color(0xFF5D0CF5)],
                ),
                label: 'Lida Value Wallet',
                subtitle: 'Manage, convert or sell your Lida Value',
                onTap: () => context.push(AppRoutes.lidaValue),
              ),
            ),
            SliverToBoxAdapter(
              child: _BrandActionTile(
                icon: Icons.stars_rounded,
                iconGradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF6C453), Color(0xFFF59E0B)],
                ),
                label: 'Lida Points & Rewards',
                subtitle: 'Track and redeem your loyalty points',
                onTap: () => context.push(AppRoutes.lidaPoints),
              ),
            ),
            SliverToBoxAdapter(
              child: _BrandActionTile(
                icon: Icons.card_giftcard_rounded,
                iconGradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1FA97A), Color(0xFF059669)],
                ),
                label: 'Invite & Earn',
                subtitle: 'Share your referral link and earn bonuses',
                badge: 'EARN',
                badgeColor: AppColors.success,
                onTap: () => context.push(AppRoutes.inviteEarn),
              ),
            ),
            SliverToBoxAdapter(
              child: _BrandActionTile(
                icon: Icons.inventory_2_rounded,
                iconGradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF00B4D8), Color(0xFF0077B6)],
                ),
                label: 'Shop Orders & Tracking',
                subtitle: 'Track your deliveries, shipments and order history',
                onTap: () => context.push('/shop/orders'),
              ),
            ),
            SliverToBoxAdapter(
              child: _BrandActionTile(
                icon: Icons.support_agent_rounded,
                iconGradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF33295E), Color(0xFF1B163E)],
                ),
                label: 'Support & Help Center',
                subtitle: '24/7 live assistance from the Lidapay team',
                badge: '24/7',
                badgeColor: AppColors.violet,
                onTap: () => context.push(AppRoutes.support),
              ),
            ),
            SliverToBoxAdapter(
              child: _BrandActionTile(
                icon: Icons.gavel_rounded,
                iconGradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4A3AFF), Color(0xFF2B1BC9)],
                ),
                label: 'Legal & Policies',
                subtitle:
                    'Privacy, terms, payments and refunds — the rules that '
                    'protect you',
                badge:
                    ref.watch(policyStatusProvider).valueOrNull?.isCurrent ==
                        false
                    ? 'REVIEW'
                    : null,
                badgeColor: AppColors.warning,
                onTap: () => context.push(AppRoutes.legal),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: InkWell(
                  onTap: _logout,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.35),
                      ),
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(
                            alpha: isDark ? 0.16 : 0.08,
                          ),
                          AppColors.violet.withValues(
                            alpha: isDark ? 0.12 : 0.05,
                          ),
                        ],
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout_rounded, color: AppColors.primary),
                        SizedBox(width: 10),
                        Text(
                          'Log out',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: Center(
                child: TextButton.icon(
                  onPressed: _isPreparingDeletionRequest
                      ? null
                      : _deleteAccount,
                  icon: const Icon(
                    Icons.delete_forever_rounded,
                    color: AppColors.error,
                    size: 18,
                  ),
                  label: Text(
                    _isPreparingDeletionRequest
                        ? 'Opening email…'
                        : 'Delete Account',
                    style: TextStyle(
                      color: AppColors.error,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 18)),
            SliverToBoxAdapter(
              child: Center(
                child: Text(
                  'Lidapay 2.0 · Milestone 2 build',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }
}

class _ProfileTopBar extends StatelessWidget {
  const _ProfileTopBar({required this.onBack, required this.onEdit});

  final VoidCallback onBack;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onBack,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Account • Rewards • Preferences',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        GestureDetector(
          onTap: onEdit,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.edit_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileBrandHero extends StatelessWidget {
  const _ProfileBrandHero({
    required this.user,
    required this.wallet,
    required this.onEdit,
    required this.onTapPoints,
    required this.onTapValue,
  });

  final UserProfile? user;
  final AsyncValue<WalletSummary> wallet;
  final VoidCallback onEdit;
  final VoidCallback onTapPoints;
  final VoidCallback onTapValue;

  String? _metaLine() {
    final u = user;
    if (u == null) return null;
    final parts = [
      if (u.username.isNotEmpty && u.username != u.phoneNumber)
        '@${u.username}',
      if (u.country.isNotEmpty) u.country.toUpperCase(),
    ];
    return parts.isEmpty ? null : parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final initial =
        (user?.firstName.isNotEmpty == true ? user!.firstName[0] : '?')
            .toUpperCase();
    final verified = user?.isVerified == true;
    final avatarUrl = user?.avatarUrl;
    final meta = _metaLine();

    Widget initialBadge() => Center(
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
      decoration: const BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: onEdit,
                      child: Stack(
                        children: [
                          Container(
                            width: 66,
                            height: 66,
                            decoration: BoxDecoration(
                              gradient: AppColors.brandGradient,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.22),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: avatarUrl != null
                                  ? Image.network(
                                      avatarUrl,
                                      width: 66,
                                      height: 66,
                                      fit: BoxFit.cover,
                                      webHtmlElementStrategy:
                                          WebHtmlElementStrategy.never,
                                      errorBuilder: (_, _, _) => initialBadge(),
                                    )
                                  : initialBadge(),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.verified_rounded,
                                size: 14,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  user?.fullName.isNotEmpty == true
                                      ? user!.fullName
                                      : 'Guest',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: onEdit,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: verified
                                        ? const Color(0xFF4CD97B)
                                              .withValues(alpha: 0.24)
                                        : Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.22,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        verified
                                            ? Icons.verified_user_rounded
                                            : Icons.shield_outlined,
                                        size: 12,
                                        color: verified
                                            ? const Color(0xFF6BF097)
                                            : Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        verified ? 'Verified' : 'KYC',
                                        style: TextStyle(
                                          color: verified
                                              ? const Color(0xFF6BF097)
                                              : Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (meta != null) ...[
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    meta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.72,
                                      ),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                if (user?.hasDeliveryAddress == true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.14,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.location_on_rounded,
                                          size: 11,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          user!.city,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    children: [
                      if (user?.email.isNotEmpty == true)
                        Row(
                          children: [
                            Icon(
                              Icons.mail_outline_rounded,
                              size: 15,
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                user!.email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _ContactStatusChip(verified: user!.emailVerified),
                          ],
                        ),
                      if (user?.email.isNotEmpty == true &&
                          user?.phoneNumber.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                      if (user?.phoneNumber.isNotEmpty == true)
                        Row(
                          children: [
                            Icon(
                              Icons.phone_iphone_rounded,
                              size: 15,
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                Formatters.maskedPhone(user!.phoneNumber),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _ContactStatusChip(verified: user!.phoneVerified),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          wallet.whenData((w) {
                return Row(
                  children: [
                    Expanded(
                      child: _HeroStatPill(
                        icon: Icons.account_balance_wallet_rounded,
                        iconColor: const Color(0xFFFF9EC6),
                        label: 'Wallet',
                        value: w.walletAvailable
                            ? Formatters.money(w.balance, w.currency)
                            : '—',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeroStatPill(
                        icon: Icons.stars_rounded,
                        iconColor: AppColors.gold,
                        label: 'Lida Points',
                        value: Formatters.points(w.lidaPoints),
                        onTap: onTapPoints,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeroStatPill(
                        icon: Icons.diamond_rounded,
                        iconColor: const Color(0xFFC49BFF),
                        label: 'Lida Value',
                        value: Formatters.money(w.lidaValueUnits, 'LV'),
                        onTap: onTapValue,
                      ),
                    ),
                  ],
                );
              }).value ??
              const AppSkeleton(height: 62, borderRadius: 16),
        ],
      ),
    );
  }
}

class _ContactStatusChip extends StatelessWidget {
  const _ContactStatusChip({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    final fg = verified ? const Color(0xFF6BF097) : const Color(0xFFFFD479);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified ? Icons.check_circle_rounded : Icons.schedule_rounded,
            size: 11,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            verified ? 'Verified' : 'Verify',
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStatPill extends StatelessWidget {
  const _HeroStatPill({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: iconColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeCard extends StatelessWidget {
  const _ThemeModeCard({
    required this.themeMode,
    required this.isDark,
    required this.onChanged,
  });

  final ThemeMode themeMode;
  final bool isDark;
  final ValueChanged<ThemeMode> onChanged;

  static const _options = <(ThemeMode, String, IconData)>[
    (ThemeMode.system, 'System', Icons.settings_suggest_outlined),
    (ThemeMode.light, 'Light', Icons.light_mode_outlined),
    (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.palette_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Theme Mode',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Switch between system, light and dark look',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkInput : const Color(0xFFF3F2F8),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                for (final option in _options)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(option.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          gradient: themeMode == option.$1
                              ? AppColors.brandGradient
                              : null,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: themeMode == option.$1
                              ? AppShadows.glow(
                                  AppColors.primary,
                                  alpha: 0.25,
                                  blur: 12,
                                )
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              option.$3,
                              size: 16,
                              color: themeMode == option.$1
                                  ? Colors.white
                                  : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              option.$2,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: themeMode == option.$1
                                    ? Colors.white
                                    : scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _BrandActionTile extends StatelessWidget {
  const _BrandActionTile({
    required this.icon,
    required this.iconGradient,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });

  final IconData icon;
  final LinearGradient iconGradient;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Material(
        color: isDark ? AppColors.darkSurface : Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: iconGradient,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: Colors.white, size: 23),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: (badgeColor ?? AppColors.primary)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                badge!,
                                style: TextStyle(
                                  color: badgeColor ?? AppColors.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.primary,
                    size: 20,
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

/// KYC checklist + progress — tells the user exactly what's left to unlock
/// full verification, with resend actions for pending confirmations.
class _KycProgressCard extends ConsumerWidget {
  const _KycProgressCard({required this.user});

  final UserProfile? user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final u = user;

    final items = <_KycItem>[
      _KycItem(label: 'Account created', done: true),
      _KycItem(label: 'Country set', done: u?.country.isNotEmpty == true),
      _KycItem(
        label: 'Email verified',
        done: u?.emailVerified == true,
        action: u?.emailVerified == true
            ? null
            : () => _resend(context, ref, email: true),
      ),
      _KycItem(
        label: 'Phone verified',
        done: u?.phoneVerified == true,
        action: u?.phoneVerified == true
            ? null
            : () => _resend(context, ref, email: false),
      ),
      _KycItem(
        label: 'Delivery address & GPS set',
        done: u?.hasDeliveryAddress == true,
        actionLabel: 'Set address',
        action: u?.hasDeliveryAddress == true
            ? null
            : () => context.push(AppRoutes.editProfile),
      ),
      _KycItem(
        label: 'Identity verified',
        done:
            u?.isVerified == true || (u?.kycStatus.toLowerCase() == 'approved'),
      ),
    ];
    final done = items.where((i) => i.done).length;
    final pct = done / items.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Verification progress',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '$done/${items.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: pct == 1 ? AppColors.success : AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: scheme.onSurfaceVariant.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(
                pct == 1 ? AppColors.success : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final item in items) _KycRow(item: item),
        ],
      ),
    );
  }

  static Future<void> _resend(
    BuildContext context,
    WidgetRef ref, {
    required bool email,
  }) async {
    final notifier = ref.read(authSessionProvider.notifier);
    try {
      if (email) {
        await notifier.resendEmailVerification();
      } else {
        await notifier.resendPhoneVerification();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              email
                  ? 'Verification email resent — check your inbox.'
                  : 'Verification code resent to your phone.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}

class _KycItem {
  const _KycItem({
    required this.label,
    required this.done,
    this.action,
    this.actionLabel = 'Resend',
  });

  final String label;
  final bool done;
  final VoidCallback? action;
  final String actionLabel;
}

class _KycRow extends StatelessWidget {
  const _KycRow({required this.item});

  final _KycItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            item.done ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 18,
            color: item.done ? AppColors.success : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: item.done ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (item.action != null)
            GestureDetector(
              onTap: item.action,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  item.actionLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
