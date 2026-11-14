import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/sticky_header.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/providers.dart';
import '../../history/widgets/transaction_details_sheet.dart';
import '../../notifications/providers.dart';
import '../../shop/data/shop_models.dart';
import '../../shop/providers.dart';
import '../data/dashboard_models.dart';
import '../providers.dart';
import '../widgets/flash_deals_carousel.dart';
import '../widgets/pending_topups_card.dart';
import '../widgets/services_rail.dart';
import '../widgets/transaction_tile.dart';
import '../widgets/wallet_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(walletSummaryProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(flashDealsProvider);
    ref.invalidate(rawNotificationsProvider);
    try {
      await Future.wait([
        ref.read(walletSummaryProvider.future),
        ref.read(recentTransactionsProvider.future),
        ref.read(flashDealsProvider.future),
        ref.read(rawNotificationsProvider.future),
      ]);
    } catch (_) {
      // Sections surface their own state; the refresh gesture still ends.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authSessionProvider)?.user;
    final wallet = ref.watch(walletSummaryProvider);
    final transactions = ref.watch(recentTransactionsProvider);
    final deals = ref.watch(flashDealsProvider);

    final loading =
        wallet is AsyncLoading ||
        (transactions is AsyncLoading && !transactions.hasValue) ||
        (deals is AsyncLoading && !deals.hasValue);

    // Only the wallet is critical; activity and deals render independently.
    final error = wallet.error;

    if (loading) return const Scaffold(body: AppSkeletonScreen());
    if (error != null) {
      return Scaffold(
        body: ErrorView(
          message: error.toString(),
          onRetry: () => _refresh(ref),
        ),
      );
    }

    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        edgeOffset: topInset + 76,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: StickySliverHeaderDelegate(
                height: topInset + 74,
                builder: (context, isStuck) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.heroGradient,
                    boxShadow: isStuck
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.22),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : null,
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, topInset + 12, 20, 12),
                    child: _Header(
                      firstName: user?.firstName ?? 'there',
                      avatarUrl: user?.avatarUrl,
                      unread: ref.watch(unreadNotificationsProvider),
                      onTapProfile: () => context.go(AppRoutes.profile),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(36),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child:
                    wallet.whenData((w) => WalletCard(wallet: w)).valueOrNull ??
                    const SizedBox.shrink(),
              ),
            ),
            const SliverToBoxAdapter(child: PendingTopupsCard()),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Services',
                caption: 'Everything you need, one tap away',
                onAction: () => context.go(AppRoutes.services),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 14)),
            const SliverToBoxAdapter(child: ServicesRail()),
            SliverToBoxAdapter(
              child:
                  deals
                      .whenData(
                        (data) => data.isEmpty
                            ? const SizedBox.shrink()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 30),
                                  SectionHeader(
                                    title: 'Flash deals',
                                    onAction: () => context.go(AppRoutes.shop),
                                  ),
                                  const SizedBox(height: 16),
                                  FlashDealsCarousel(
                                    deals: data,
                                    onDealTap: (deal) {
                                      final catalog =
                                          ref
                                              .read(shopProductsProvider)
                                              .valueOrNull ??
                                          const <ShopProduct>[];
                                      ShopProduct target = deal.toShopProduct();
                                      for (final p in catalog) {
                                        if (deal.productId != null &&
                                            p.id == deal.productId) {
                                          target = p;
                                          break;
                                        }
                                        if (p.name.toLowerCase() ==
                                                deal.title.toLowerCase() ||
                                            deal.title.toLowerCase().contains(
                                              p.name.toLowerCase(),
                                            ) ||
                                            p.name.toLowerCase().contains(
                                              deal.title.toLowerCase(),
                                            )) {
                                          target = p;
                                          break;
                                        }
                                      }
                                      ref
                                              .read(
                                                pendingShopProductProvider
                                                    .notifier,
                                              )
                                              .state =
                                          target;
                                      context.go(AppRoutes.shop);
                                    },
                                  ),
                                ],
                              ),
                      )
                      .valueOrNull ??
                  const SizedBox.shrink(),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 30)),
            SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Recent activity',
                onAction: () => context.go(AppRoutes.history),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 6)),
            SliverToBoxAdapter(
              child:
                  transactions
                      .whenData(
                        (data) => data.isEmpty
                            ? const EmptyView(
                                title: 'No transactions yet',
                                subtitle:
                                    'Your recent activity will show up here.',
                              )
                            : _ActivityGroups(
                                groups: _groupByDay(data),
                                onTap: (t) => showTransactionDetails(
                                  context,
                                  t,
                                  userPhone: user?.phoneNumber ?? '',
                                ),
                              ),
                      )
                      .valueOrNull ??
                  const SizedBox.shrink(),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  static Map<String, List<Transaction>> _groupByDay(List<Transaction> items) {
    final groups = <String, List<Transaction>>{};
    for (final t in items) {
      groups.putIfAbsent(_dayLabel(t.createdAt), () => []).add(t);
    }
    return groups;
  }

  static String _dayLabel(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    return switch (today.difference(day).inDays) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => DateFormat('d MMM').format(local),
    };
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.firstName,
    required this.unread,
    this.avatarUrl,
    this.onTapProfile,
  });

  final String firstName;
  final int unread;
  final String? avatarUrl;
  final VoidCallback? onTapProfile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = firstName.trim().isEmpty
        ? 'T'
        : firstName.trim()[0].toUpperCase();

    Widget fallbackInitial() => Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    return Row(
      children: [
        GestureDetector(
          onTap: onTapProfile,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.45),
                width: 1.5,
              ),
            ),
            child: ClipOval(
              child: avatarUrl != null
                  ? Image.network(
                      avatarUrl!,
                      width: 46,
                      height: 46,
                      fit: BoxFit.cover,
                      webHtmlElementStrategy: WebHtmlElementStrategy.never,
                      errorBuilder: (_, _, _) => fallbackInitial(),
                    )
                  : fallbackInitial(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, $firstName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Welcome back to Lidapay',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: Colors.white.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: () => context.push(AppRoutes.notifications),
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 46,
              height: 46,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.notifications_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                  if (unread > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 17),
                        height: 17,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: AppColors.navy, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          unread > 9 ? '9+' : '$unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityGroups extends StatelessWidget {
  const _ActivityGroups({required this.groups, required this.onTap});

  final Map<String, List<Transaction>> groups;
  final ValueChanged<Transaction> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
            child: Text(
              entry.key,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SurfaceCard(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 74, endIndent: 16),
                  TransactionRow(
                    transaction: entry.value[i],
                    onTap: () => onTap(entry.value[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
