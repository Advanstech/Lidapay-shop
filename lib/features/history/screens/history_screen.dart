import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/sticky_header.dart';
import '../../auth/providers.dart';
import '../../dashboard/data/dashboard_models.dart';
import '../data/history_models.dart';
import '../providers.dart';
import '../widgets/history_filter_sheet.dart';
import '../widgets/transaction_details_sheet.dart';

/// Full activity ledger — filterable, grouped by day, pull-to-refresh, with
/// summary stats and a full-height Transaction Details view.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  static const _filters =
      <({TransactionType? type, String label, IconData icon})>[
        (type: null, label: 'All', icon: Icons.grid_view_rounded),
        (
          type: TransactionType.airtime,
          label: 'Airtime',
          icon: Icons.phone_iphone_rounded,
        ),
        (type: TransactionType.data, label: 'Data', icon: Icons.wifi_rounded),
        (
          type: TransactionType.walletTopUp,
          label: 'MoMo',
          icon: Icons.account_balance_wallet_rounded,
        ),
        (
          type: TransactionType.shopOrder,
          label: 'Shop',
          icon: Icons.shopping_bag_rounded,
        ),
        (
          type: TransactionType.lidaValue,
          label: 'Lida Value',
          icon: Icons.diamond_rounded,
        ),
      ];

  Future<void> _refresh(WidgetRef ref) =>
      ref.read(historyProvider.notifier).load();

  Future<void> _openFilterSheet(BuildContext context, WidgetRef ref) async {
    final current =
        ref.read(historyProvider).valueOrNull?.filter ?? const HistoryFilter();
    final result = await HistoryFilterSheet.show(context, initial: current);
    if (result != null) {
      await ref.read(historyProvider.notifier).setFilter(result);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final activeFilter = history.valueOrNull?.filter ?? const HistoryFilter();
    final userPhone =
        ref.watch(authSessionProvider)?.user.phoneNumber ?? '0244588584';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: history.when(
        loading: () => ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: const [
            AppSkeleton(height: 168, borderRadius: 24),
            SizedBox(height: 16),
            Row(
              children: [
                AppSkeleton(width: 76, height: 40, borderRadius: 20),
                SizedBox(width: 8),
                AppSkeleton(width: 96, height: 40, borderRadius: 20),
                SizedBox(width: 8),
                AppSkeleton(width: 84, height: 40, borderRadius: 20),
              ],
            ),
            SizedBox(height: 20),
            AppSkeleton(height: 82, borderRadius: 20),
            SizedBox(height: 12),
            AppSkeleton(height: 82, borderRadius: 20),
            SizedBox(height: 12),
            AppSkeleton(height: 82, borderRadius: 20),
          ],
        ),
        error: (error, _) =>
            ErrorView(message: error.toString(), onRetry: () => _refresh(ref)),
        data: (state) {
          double moneyIn = 0;
          double moneyOut = 0;
          int pendingCount = 0;
          for (final t in state.items) {
            if (t.status == TransactionStatus.pending) {
              pendingCount++;
            }
            // Money stats only count cash rows — LV/PTS units don't
            // belong in a GHS total.
            if (t.currency == 'GHS') {
              if (t.isMoneyIn) {
                moneyIn += t.amount;
              } else {
                moneyOut += t.amount;
              }
            }
          }

          final grouped = _groupByDay(state.items);
          final topInset = MediaQuery.paddingOf(context).top;
          final scaffoldBg = isDark
              ? AppColors.darkScaffold
              : AppColors.lightScaffold;

          return RefreshIndicator(
            onRefresh: () => _refresh(ref),
            edgeOffset: topInset + 72,
            child: CustomScrollView(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: StickySliverHeaderDelegate(
                    height: topInset + 68,
                    builder: (context, isStuck) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: scaffoldBg,
                        border: Border(
                          bottom: BorderSide(
                            color: isStuck
                                ? Theme.of(context).colorScheme.outlineVariant
                                : Colors.transparent,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20, topInset + 10, 20, 10),
                        child: _ActivityTopBar(
                          onBack: () => context.go(AppRoutes.home),
                          onAnalytics: () =>
                              context.push(AppRoutes.historyAnalytics),
                          onFilter: () => _openFilterSheet(context, ref),
                          filterActive: activeFilter.isActive,
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _ActivityHeroStats(
                    moneyIn: moneyIn,
                    moneyOut: moneyOut,
                    pendingCount: pendingCount,
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: StickySliverHeaderDelegate(
                    height: 62,
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
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _filters.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final filter = _filters[index];
                            final isSelected = filter.type == null
                                ? activeFilter.types.isEmpty
                                : activeFilter.types.length == 1 &&
                                      activeFilter.types.contains(filter.type);
                            return _ActivityFilterChip(
                              icon: filter.icon,
                              label: filter.label,
                              selected: isSelected,
                              onTap: () => ref
                                  .read(historyProvider.notifier)
                                  .setTypeFilter(filter.type),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                if (state.items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ActivityEmptyView(
                      filter: activeFilter.types.length == 1
                          ? activeFilter.types.first
                          : null,
                      isFiltered: activeFilter.isActive,
                      onClearFilter: () => ref
                          .read(historyProvider.notifier)
                          .setFilter(const HistoryFilter()),
                      onRefresh: () => _refresh(ref),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        if (index == grouped.length) {
                          if (state.hasMore) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              ref.read(historyProvider.notifier).loadMore();
                            });
                          }
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              ),
                            ),
                          );
                        }
                        final entry = grouped[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 4,
                                  bottom: 10,
                                ),
                                child: Text(
                                  entry.$1,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white70
                                        : const Color(0xFF91949E),
                                  ),
                                ),
                              ),
                              for (var i = 0; i < entry.$2.length; i++) ...[
                                if (i > 0) const SizedBox(height: 12),
                                _ActivityTransactionCard(
                                  transaction: entry.$2[i],
                                  onTap: () => showTransactionDetails(
                                    context,
                                    entry.$2[i],
                                    userPhone: userPhone,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }, childCount: grouped.length + (state.hasMore ? 1 : 0)),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static List<(String, List<Transaction>)> _groupByDay(
    List<Transaction> items,
  ) {
    final map = <String, List<Transaction>>{};
    for (final t in items) {
      final label = _dayLabel(t.createdAt);
      map.putIfAbsent(label, () => []).add(t);
    }
    return map.entries.map((e) => (e.key, e.value)).toList();
  }

  static String _dayLabel(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff > 1 && diff < 7) return DateFormat('EEEE').format(local);
    return DateFormat('MMM d').format(local);
  }
}

class _ActivityTopBar extends StatelessWidget {
  const _ActivityTopBar({
    required this.onBack,
    required this.onAnalytics,
    required this.onFilter,
    required this.filterActive,
  });

  final VoidCallback onBack;
  final VoidCallback onAnalytics;
  final VoidCallback onFilter;
  final bool filterActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: onBack,
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'History',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: scheme.onSurface,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Every transaction, in one place',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onAnalytics,
          tooltip: 'Insights',
          icon: Icon(Icons.assessment_outlined, color: scheme.onSurface),
        ),
        IconButton(
          onPressed: onFilter,
          tooltip: 'Filter',
          icon: Badge(
            isLabelVisible: filterActive,
            smallSize: 8,
            backgroundColor: AppColors.warning,
            child: Icon(Icons.filter_list_rounded, color: scheme.onSurface),
          ),
        ),
      ],
    );
  }
}

class _ActivityHeroStats extends StatelessWidget {
  const _ActivityHeroStats({
    required this.moneyIn,
    required this.moneyOut,
    required this.pendingCount,
  });

  final double moneyIn;
  final double moneyOut;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: _SummaryStatPill(
              icon: Icons.south_west_rounded,
              iconColor: AppColors.success,
              label: 'Money In',
              labelColor: AppColors.success,
              value: 'GHS ${moneyIn.toStringAsFixed(2)}',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryStatPill(
              icon: Icons.north_east_rounded,
              iconColor: AppColors.primary,
              label: 'Money Out',
              labelColor: AppColors.primary,
              value: 'GHS ${moneyOut.toStringAsFixed(2)}',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryStatPill(
              icon: Icons.access_time_rounded,
              iconColor: AppColors.warning,
              label: 'Pending',
              labelColor: AppColors.warning,
              value: '$pendingCount',
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStatPill extends StatelessWidget {
  const _SummaryStatPill({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityFilterChip extends StatelessWidget {
  const _ActivityFilterChip({
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
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isDark ? Colors.white12 : const Color(0xFFE4E2EA)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : scheme.onSurface,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : scheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityEmptyView extends StatelessWidget {
  const _ActivityEmptyView({
    required this.filter,
    required this.isFiltered,
    required this.onClearFilter,
    required this.onRefresh,
  });

  final TransactionType? filter;
  final bool isFiltered;
  final VoidCallback onClearFilter;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final isShop = filter == TransactionType.shopOrder;
    final title = isShop ? 'No shop orders yet' : 'No transactions';
    final subtitle = isFiltered
        ? 'Nothing matches these filters.'
        : isShop
        ? 'Your shop orders will appear here.'
        : 'Nothing matches this filter yet.';
    final icon = isFiltered
        ? Icons.filter_alt_off_rounded
        : isShop
        ? Icons.shopping_bag_outlined
        : Icons.receipt_long_outlined;

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 110),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 54, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isFiltered) ...[
                  GestureDetector(
                    onTap: onClearFilter,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.filter_alt_off_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Clear filters',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 26),
                ],
                GestureDetector(
                  onTap: onRefresh,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Refresh',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                    ],
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

class _ActivityTransactionCard extends StatelessWidget {
  const _ActivityTransactionCard({
    required this.transaction,
    required this.onTap,
  });

  final Transaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final title = transaction.description.isNotEmpty
        ? transaction.description
        : (transaction.counterparty ?? transaction.type.label);
    final timeStr = DateFormat('h:mm a')
        .format(transaction.createdAt.toLocal());
    final subtitle = '${transaction.type.label} · $timeStr';

    final (statusColor, statusBg, statusText) = switch (transaction.status) {
      TransactionStatus.success => (
        const Color(0xFF33B457),
        const Color(0xFFEAF8EE),
        'Completed',
      ),
      TransactionStatus.pending => (
        AppColors.warning,
        const Color(0xFFFFF4E5),
        'Pending',
      ),
      TransactionStatus.failed => (
        AppColors.error,
        const Color(0xFFFDECEC),
        'Failed',
      ),
    };

    final iconData = switch (transaction.type) {
      TransactionType.airtime => Icons.phone_iphone_rounded,
      TransactionType.data => Icons.wifi_rounded,
      TransactionType.shopOrder => Icons.shopping_bag_outlined,
      TransactionType.lidaValue => Icons.diamond_outlined,
      TransactionType.walletTopUp => Icons.account_balance_wallet_outlined,
      TransactionType.other => Icons.receipt_long_rounded,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFEC3281), Color(0xFF8C36F5)],
                ),
                borderRadius: BorderRadius.circular(15),
              ),
              alignment: Alignment.center,
              child: Icon(iconData, color: Colors.white, size: 25),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${transaction.isMoneyIn ? '+' : '−'}${Formatters.money(transaction.amount, transaction.currency)}',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: transaction.status == TransactionStatus.failed
                        ? scheme.onSurfaceVariant
                        : (transaction.isMoneyIn
                              ? const Color(0xFF33B457)
                              : scheme.onSurface),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? statusColor.withValues(alpha: 0.16)
                        : statusBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
