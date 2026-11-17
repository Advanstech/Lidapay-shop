import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/skeleton.dart';
import '../data/shop_models.dart';
import '../providers.dart';
import '../widgets/driver_location_map.dart';

void _openOrderDetailSheet(BuildContext context, ShopOrder order) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OrderDetailSheet(order: order),
  );
}

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key, this.initialOrderId});

  final String? initialOrderId;

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  bool _didOpenInitialOrder = false;

  void _maybeOpenInitialOrder(List<ShopOrder>? orders) {
    final targetId = widget.initialOrderId?.trim();
    if (targetId == null ||
        targetId.isEmpty ||
        _didOpenInitialOrder ||
        orders == null) {
      return;
    }
    ShopOrder? matchedOrder;
    for (final order in orders) {
      if (order.id == targetId || order.reference == targetId) {
        matchedOrder = order;
        break;
      }
    }
    if (matchedOrder == null) return;
    _didOpenInitialOrder = true;
    final selected = matchedOrder;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openOrderDetailSheet(context, selected);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(userOrdersProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final orders = ordersAsync.valueOrNull;
    _maybeOpenInitialOrder(orders);

    final inTransit =
        orders
            ?.where(
              (o) => const {
                'shipped',
                'out_for_delivery',
                'processing',
                'paid',
              }.contains(o.status.toLowerCase()),
            )
            .length ??
        0;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkScaffold : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(userOrdersProvider.future),
        edgeOffset: MediaQuery.paddingOf(context).top + 110,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _OrdersHero(
                count: orders?.length ?? 0,
                inTransit: inTransit,
                onRefresh: () => ref.invalidate(userOrdersProvider),
              ),
            ),
            switch ((ordersAsync.isLoading, ordersAsync.hasError, orders)) {
              (true, _, _) || (_, _, null) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: const [
                      AppSkeleton(height: 110, borderRadius: 22),
                      SizedBox(height: 12),
                      AppSkeleton(height: 110, borderRadius: 22),
                      SizedBox(height: 12),
                      AppSkeleton(height: 110, borderRadius: 22),
                    ],
                  ),
                ),
              ),
              (false, true, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorView(
                  message: 'Could not load your orders.',
                  onRetry: () => ref.invalidate(userOrdersProvider),
                ),
              ),
              (false, false, final list) when list!.isEmpty =>
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyOrders(onExplore: () => context.go('/shop')),
                ),
              (false, false, final list) => SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  MediaQuery.paddingOf(context).bottom + 24,
                ),
                sliver: SliverList.separated(
                  itemCount: list!.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) =>
                      _OrderCard(order: list[index]),
                ),
              ),
            },
          ],
        ),
      ),
    );
  }
}

/// Gradient header shared with Cart/Points — title, counts, live refresh.
class _OrdersHero extends StatelessWidget {
  const _OrdersHero({
    required this.count,
    required this.inTransit,
    required this.onRefresh,
  });

  final int count;
  final int inTransit;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        22,
        MediaQuery.paddingOf(context).top + 14,
        22,
        24,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                color: Colors.white,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                color: Colors.white,
                tooltip: 'Refresh orders',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'My Orders',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            count == 0
                ? 'Track every purchase and delivery in one place.'
                : '$count ${count == 1 ? 'order' : 'orders'}'
                      '${inTransit > 0 ? ' · $inTransit in transit' : ''}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders({required this.onExplore});

  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.shopping_bag_outlined,
                size: 44,
                color: AppColors.primary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No orders yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'When you shop on LidaPay, your orders and delivery tracking will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 26),
            AppButton(label: 'Explore Shop', onPressed: onExplore),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order});

  final ShopOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final dateStr = DateFormat('dd MMM yyyy · HH:mm').format(order.placedAt);

    final (statusColor, statusIcon, statusLabel) = switch (order.status
        .toLowerCase()) {
      'delivered' => (
        AppColors.success,
        Icons.check_circle_rounded,
        'Delivered',
      ),
      'shipped' || 'out_for_delivery' => (
        AppColors.navy,
        Icons.local_shipping_rounded,
        'In Transit',
      ),
      'processing' || 'paid' => (
        const Color(0xFFF2994A),
        Icons.inventory_2_rounded,
        'Processing',
      ),
      'cancelled' => (scheme.error, Icons.cancel_rounded, 'Cancelled'),
      _ => (scheme.onSurfaceVariant, Icons.schedule_rounded, 'Pending'),
    };

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openOrderDetailSheet(context, order),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.shopping_bag_outlined,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.reference,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Placed $dateStr',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 13, color: statusColor),
                          const SizedBox(width: 5),
                          Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white10 : const Color(0xFFF0EEF5),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '${order.itemCount} '
                      '${order.itemCount == 1 ? 'item' : 'items'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${order.currency} ${order.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Row(
                  children: [
                    Text(
                      'Track order',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderDetailSheet extends ConsumerWidget {
  const _OrderDetailSheet({required this.order});

  final ShopOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final trackingAsync = ref.watch(orderTrackingProvider(order.id));

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkScaffold : theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Order Details',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        order.reference,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${order.currency} ${order.total.toStringAsFixed(2)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Delivery Tracking',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StatusPill(status: order.status),
                    if (order.trackingNumber != null) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: order.trackingNumber!),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Tracking number copied'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 150,
                                ),
                                child: Text(
                                  '${order.carrier != null ? '${order.carrier} · ' : ''}${order.trackingNumber}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.copy_rounded,
                                size: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            trackingAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    AppSkeleton(height: 40, borderRadius: 12),
                    SizedBox(height: 8),
                    AppSkeleton(height: 40, borderRadius: 12),
                  ],
                ),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Tracking update unavailable: $err'),
              ),
              data: (tracking) {
                if (tracking == null || tracking.events.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Package is being prepared at our fulfillment center.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Live driver pin — courier partner streams GPS fixes to
                    // `lastDriverLocation` once the parcel is picked up.
                    if (tracking.lastDriverLocation != null &&
                        !tracking.isTerminal) ...[
                      DriverLocationMap(location: tracking.lastDriverLocation!),
                      const SizedBox(height: 14),
                    ],
                    if (tracking.deliveredAt != null ||
                        tracking.estimatedDeliveryDate != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            Icon(
                              tracking.deliveredAt != null
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.schedule_rounded,
                              size: 16,
                              color: tracking.deliveredAt != null
                                  ? AppColors.success
                                  : AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                tracking.deliveredAt != null
                                    ? 'Delivered ${DateFormat('dd MMM yyyy · HH:mm').format(tracking.deliveredAt!)}'
                                    : 'Estimated delivery ${DateFormat('dd MMM yyyy').format(tracking.estimatedDeliveryDate!)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: tracking.deliveredAt != null
                                      ? AppColors.success
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    for (var i = 0; i < tracking.events.length; i++)
                      _TrackingEventRow(
                        event: tracking.events[i],
                        isLast: i == tracking.events.length - 1,
                        isLatest: i == 0,
                      ),
                  ],
                );
              },
            ),
            if (order.items.isNotEmpty) ...[
              const Divider(height: 28),
              const Text(
                'Items in this order',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...order.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.quantity}× ${item.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // SKU is the fulfilment key the courier/partner
                            // picks by — surface it when the snapshot has one.
                            if (item.sku != null && item.sku!.isNotEmpty)
                              Text(
                                'SKU ${item.sku}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  letterSpacing: 0.3,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${order.currency} ${(item.price * item.quantity).toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (order.subtotal != null ||
                (order.discount ?? 0) > 0 ||
                (order.deliveryFee ?? 0) > 0) ...[
              const Divider(height: 28),
              if (order.subtotal != null)
                _OrderTotalRow(
                  label: 'Subtotal',
                  value:
                      '${order.currency} ${order.subtotal!.toStringAsFixed(2)}',
                ),
              if ((order.discount ?? 0) > 0)
                _OrderTotalRow(
                  label: 'Discount',
                  value:
                      '-${order.currency} ${order.discount!.toStringAsFixed(2)}',
                ),
              if ((order.deliveryFee ?? 0) > 0)
                _OrderTotalRow(
                  label: 'Delivery fee',
                  value:
                      '${order.currency} ${order.deliveryFee!.toStringAsFixed(2)}',
                ),
              _OrderTotalRow(
                label: 'Total',
                value: '${order.currency} ${order.total.toStringAsFixed(2)}',
                emphasized: true,
              ),
            ],
            if (order.shippingAddress != null) ...[
              const Divider(height: 28),
              const Text(
                'Deliver to',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                order.shippingAddress!.fullName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                order.shippingAddress!.summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (order.shippingAddress!.phone.isNotEmpty)
                Text(
                  order.shippingAddress!.phone,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
            if (order.canBeCancelled) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel Order'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => _confirmCancel(context, ref),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _confirmCancel(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Cancel Order?'),
        content: const Text(
          'Are you sure you want to cancel this order? If paid, a refund will be processed to your original payment method.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Keep Order'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              Navigator.pop(context);
              try {
                await ref.read(shopRepositoryProvider).cancelOrder(order.id);
                ref.invalidate(userOrdersProvider);
                HapticFeedback.mediumImpact();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not cancel order: $e')),
                  );
                }
              }
            },
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }
}

/// Money row in the order-detail totals block.
class _OrderTotalRow extends StatelessWidget {
  const _OrderTotalRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
              color: emphasized ? AppColors.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Order lifecycle pill for the tracking header — maps the backend status
/// (`pending → paid → processing → shipped → delivered`, plus cancelled /
/// refunded) onto a short customer-facing label.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  static const _labels = {
    'pending': ('Placed', AppColors.warning),
    'paid': ('Paid', AppColors.primary),
    'processing': ('Processing', AppColors.violet),
    'shipped': ('Shipped', AppColors.primary),
    'delivered': ('Delivered', AppColors.success),
    'cancelled': ('Cancelled', AppColors.error),
    'refunded': ('Refunded', AppColors.error),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final normalized = status.toLowerCase();
    final (label, color) =
        _labels[normalized] ??
        (normalized.isEmpty ? 'Placed' : normalized, scheme.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

/// Timeline row for a tracking event — dot + connector line.
class _TrackingEventRow extends StatelessWidget {
  const _TrackingEventRow({
    required this.event,
    required this.isLast,
    required this.isLatest,
  });

  final dynamic event;
  final bool isLast;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = event.timestamp != null
        ? DateFormat('dd MMM · HH:mm').format(event.timestamp!)
        : '';
    final dotColor = isLatest ? AppColors.primary : scheme.outlineVariant;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                  border: isLatest
                      ? Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          width: 3,
                        )
                      : null,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.message.toString(),
                    style: TextStyle(
                      fontWeight: isLatest ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  if (event.location != null)
                    Text(
                      event.location.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (time.isNotEmpty)
                    Text(
                      time,
                      style: TextStyle(fontSize: 11.5, color: scheme.outline),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
