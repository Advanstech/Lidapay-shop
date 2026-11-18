import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/surface_card.dart';
import '../data/shop_models.dart';

/// Shown after a confirmed shop payment. The order already carries the
/// shipping address collected before checkout — fulfilment and delivery are
/// handled by the shop, so this screen only confirms and points at tracking.
/// Per the shop contract there is no client-side courier selection, courier
/// quote or GPS capture here.
class CheckoutSuccessScreen extends ConsumerWidget {
  const CheckoutSuccessScreen({
    super.key,
    required this.order,
    this.deliveryAddress,
  });

  final ShopOrder order;

  /// The address submitted at checkout — used when the order payload does
  /// not echo `shippingAddress` back.
  final ShippingAddress? deliveryAddress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final address = order.shippingAddress ?? deliveryAddress;

    return Scaffold(
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.paddingOf(context).top + 14,
              20,
              22,
            ),
            decoration: const BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
            child: Column(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.72, end: 1),
                  duration: const Duration(milliseconds: 620),
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.38),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Payment Confirmed!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Order ${order.reference} is placed — the shop prepares and '
                  'delivers it to your address.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                SurfaceCard(
                  padding: const EdgeInsets.all(18),
                  radius: 22,
                  child: Column(
                    children: [
                      _OrderRow(
                        label: 'Order Reference',
                        value: order.reference,
                      ),
                      const SizedBox(height: 10),
                      _OrderRow(
                        label: 'Items Paid',
                        value:
                            '${order.itemCount} ${order.itemCount == 1 ? 'item' : 'items'}',
                      ),
                      const SizedBox(height: 10),
                      _OrderRow(
                        label: 'Date',
                        value: Formatters.dateTime(order.placedAt),
                      ),
                      if (order.discount != null && order.discount! > 0) ...[
                        const SizedBox(height: 10),
                        _OrderRow(
                          label: 'Discount',
                          value: '-${Formatters.currency(order.discount!)}',
                        ),
                      ],
                      if (order.deliveryFee != null &&
                          order.deliveryFee! > 0) ...[
                        const SizedBox(height: 10),
                        _OrderRow(
                          label: 'Delivery Fee',
                          value: Formatters.currency(order.deliveryFee!),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Divider(height: 1, color: scheme.outlineVariant),
                      const SizedBox(height: 12),
                      _OrderRow(
                        label: 'Total Paid',
                        value: Formatters.currency(order.total),
                        emphasized: true,
                      ),
                    ],
                  ),
                ),
                if (address != null) ...[
                  const SizedBox(height: 16),
                  SurfaceCard(
                    padding: const EdgeInsets.all(18),
                    radius: 22,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Deliver To',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                address.fullName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                address.summary,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: scheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                              if (address.phone.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  address.phone,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              if (address.deliveryInstructions.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '“${address.deliveryInstructions}”',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SurfaceCard(
                  padding: const EdgeInsets.all(14),
                  radius: 18,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.local_shipping_outlined,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Fulfilment and delivery are arranged by the '
                          'shop. Follow progress and courier updates in '
                          'My Orders.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                AppButton(
                  label: 'Track Order',
                  icon: const Icon(
                    Icons.local_shipping_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    if (context.canPop()) {
                      Navigator.of(context).pop();
                      context.pushReplacement(AppRoutes.orders);
                    } else {
                      context.go(AppRoutes.orders);
                    }
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    if (context.canPop()) {
                      Navigator.of(context).pop();
                      if (context.canPop()) context.pop();
                    } else {
                      context.go(AppRoutes.shop);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Back to Shop',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.go(AppRoutes.history),
                  child: const Text('View in History'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = emphasized
        ? TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: scheme.primary,
          )
        : Theme.of(context).textTheme.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Flexible(
          child: Text(value, style: style, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
