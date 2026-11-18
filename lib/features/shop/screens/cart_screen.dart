import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/product_image.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/providers.dart';
import '../../payments/data/pending_payment.dart';
import '../../payments/providers.dart';
import '../../payments/widgets/payment_awaiting_panel.dart';
import '../../payments/widgets/payment_method_selector.dart';
import '../data/shop_models.dart';
import '../providers.dart';
import '../widgets/shipping_address_sheet.dart';
import 'checkout_success_screen.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen>
    with WidgetsBindingObserver {
  bool _checkingOut = false;
  ShopOrder? _pendingOrder;
  ShippingAddress? _pendingAddress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(paymentSessionProvider).phase ==
            PaymentPhase.awaitingCallback) {
      ref.read(paymentSessionProvider.notifier).recheck();
    }
  }

  /// Contract order: collect the postal delivery address (with optional map pin),
  /// create the order via `POST /api/v1/shop/checkout` so the backend calculates
  /// `deliveryFee` from its rate card, show the final `order.total` to the
  /// customer, and then launch ExpressPay (`card`).
  Future<void> _checkout() async {
    final user = ref.read(authSessionProvider)?.user;
    final cartData = ref.read(cartProvider).valueOrNull;
    if (cartData == null || cartData.items.isEmpty) return;

    final address = await showShippingAddressSheet(
      context: context,
      user: user,
      initial: _pendingAddress,
    );
    if (!mounted || address == null) return;

    setState(() => _checkingOut = true);
    final order = await ref
        .read(cartProvider.notifier)
        .checkout(address, paymentMethod: 'card');
    if (!mounted) return;
    setState(() => _checkingOut = false);

    if (order == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checkout failed — your cart is unchanged. Try again.'),
        ),
      );
      return;
    }
    _pendingOrder = order;
    _pendingAddress = address;
    ref.read(lastOrderProvider.notifier).state = order;

    final fee = order.deliveryFee ?? 0;
    final summaryParts = <String>[
      'Order ${order.reference}',
      '${cartData.itemCount} ${cartData.itemCount == 1 ? 'item' : 'items'}',
      if (fee > 0) 'Delivery ${Formatters.currency(fee)}',
    ];
    final choice = await showPaymentMethodSheet(
      context: context,
      amountLabel: Formatters.currency(order.total),
      orderSummary: summaryParts.join(' · '),
      registeredNumber: user?.contactPhone ?? '',
      showMobileMoney: false,
    );
    if (!mounted || choice == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Order ${order.reference} was placed — complete payment from My Orders.',
            ),
          ),
        );
      }
      return;
    }

    final launched = await ref
        .read(paymentSessionProvider.notifier)
        .beginPayment(
          PendingPayment.shopOrder(
            reference: newPaymentReference(),
            clientReference: newClientReference(),
            orderId: order.id,
            orderNumber: order.reference,
            total: order.total,
            currency: order.currency,
          ),
          method: choice.method,
          momoNumber: choice.momoNumber,
        );
    if (!launched && mounted) {
      final message = ref.read(paymentSessionProvider).message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message ??
                'Order ${order.reference} was created but payment could not '
                    'be started — retry from your orders.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cart = ref.watch(cartProvider);
    final cartData = cart.valueOrNull;

    ref.listen<PaymentSessionState>(paymentSessionProvider, (prev, next) {
      if (!mounted) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
        if (next.phase == PaymentPhase.completed) {
          ref.invalidate(userOrdersProvider);
          ref.invalidate(ordersControllerProvider);
        }
        return;
      }
      if (next.phase == PaymentPhase.completed &&
          next.shopOrderNumber != null) {
        final order =
            _pendingOrder ??
            ref.read(lastOrderProvider) ??
            ShopOrder(
              id: next.shopOrderNumber!,
              reference: next.shopOrderNumber!,
              itemCount: 1,
              total: 0,
              currency: 'GHS',
              placedAt: DateTime.now(),
              paymentStatus: 'paid',
              status: 'processing',
            );
        _pendingOrder = null;
        ref.read(paymentSessionProvider.notifier).reset();
        ref.invalidate(userOrdersProvider);
        ref.invalidate(ordersControllerProvider);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CheckoutSuccessScreen(
              order: order,
              deliveryAddress: _pendingAddress,
            ),
          ),
        );
      } else if (next.phase == PaymentPhase.failed &&
          prev?.phase != PaymentPhase.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message ?? 'Payment could not be completed.'),
          ),
        );
      }
    });

    final paymentActive = ref.watch(
      paymentSessionProvider.select(
        (s) => s.phase != PaymentPhase.idle && s.pending != null,
      ),
    );
    final itemCount = cart.valueOrNull?.itemCount ?? 0;

    return Scaffold(
      body: Column(
        children: [
          _CartHeroHeader(
            itemCount: itemCount,
            canClear:
                (cart.valueOrNull?.items.isNotEmpty ?? false) && !paymentActive,
            onBack: () => context.pop(),
            onOpenOrders: () => context.push(AppRoutes.orders),
            onClear: () => ref.read(cartProvider.notifier).clear(),
          ),
          Expanded(
            child: paymentActive
                ? const PaymentAwaitingPanel()
                : cartData == null
                ? (cart.isLoading
                      ? ListView(
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(20),
                          children: const [
                            AppSkeleton(height: 92, borderRadius: 24),
                            SizedBox(height: 12),
                            AppSkeleton(height: 92, borderRadius: 24),
                            SizedBox(height: 12),
                            AppSkeleton(height: 92, borderRadius: 24),
                            SizedBox(height: 24),
                            AppSkeleton(height: 120, borderRadius: 24),
                          ],
                        )
                      : ErrorView(
                          message:
                              cart.error?.toString() ??
                              'Could not load your cart.',
                          onRetry: () => ref.read(cartProvider.notifier).load(),
                        ))
                : cartData.items.isEmpty
                ? EmptyView(
                    title: 'Your cart is empty',
                    subtitle: 'Browse the shop and add something you like.',
                    icon: Icons.shopping_cart_outlined,
                    action: TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('Continue shopping'),
                    ),
                  )
                : Column(
                    children: [
                      if (cart.isLoading && cart.hasValue)
                        const LinearProgressIndicator(
                          minHeight: 2,
                          backgroundColor: Colors.transparent,
                        ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                          itemCount: cartData.items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) => _CartLine(
                            item: cartData.items[index],
                            updating: cart is AsyncLoading,
                          ),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.fromLTRB(
                          22,
                          18,
                          22,
                          MediaQuery.paddingOf(context).bottom + 18,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurface : Colors.white,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                          border: Border(
                            top: BorderSide(
                              color: isDark
                                  ? Colors.white10
                                  : const Color(0xFFECEAF2),
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.35 : 0.06,
                              ),
                              blurRadius: 20,
                              offset: const Offset(0, -6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _SummaryRow(
                              label:
                                  'Subtotal (${cartData.itemCount} ${cartData.itemCount == 1 ? 'item' : 'items'})',
                              value: Formatters.currency(cartData.subtotal),
                            ),
                            if (cartData.discount > 0) ...[
                              const SizedBox(height: 8),
                              _SummaryRow(
                                label: 'Discount',
                                value:
                                    '-${Formatters.currency(cartData.discount)}',
                                valueColor: AppColors.success,
                              ),
                            ],
                            const SizedBox(height: 8),
                            const _SummaryRow(
                              label: 'Delivery fee',
                              value: 'Set at checkout',
                            ),
                            const SizedBox(height: 12),
                            Divider(
                              height: 1,
                              color: Theme.of(context).dividerColor,
                            ),
                            const SizedBox(height: 12),
                            _SummaryRow(
                              label: 'Total',
                              value: Formatters.currency(cartData.total),
                              emphasized: true,
                            ),
                            const SizedBox(height: 16),
                            AppButton(
                              label:
                                  'Pay · ${Formatters.currency(cartData.total)}',
                              icon: const Icon(
                                Icons.lock_outline_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              loading: _checkingOut,
                              onPressed: _checkingOut ? null : _checkout,
                            ),
                          ],
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

class _CartHeroHeader extends StatelessWidget {
  const _CartHeroHeader({
    required this.itemCount,
    required this.canClear,
    required this.onBack,
    required this.onOpenOrders,
    required this.onClear,
  });

  final int itemCount;
  final bool canClear;
  final VoidCallback onBack;
  final VoidCallback onOpenOrders;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topInset + 12, 20, 18),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          _HeaderIconBtn(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onTap: onBack,
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
                        'My Cart',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (itemCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Review your items before checkout',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _HeaderIconBtn(
            icon: Icons.local_shipping_outlined,
            tooltip: 'My Orders & Courier Tracking',
            onTap: onOpenOrders,
          ),
          if (canClear) ...[
            const SizedBox(width: 8),
            _HeaderIconBtn(
              icon: Icons.delete_sweep_outlined,
              tooltip: 'Clear cart',
              onTap: onClear,
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  const _HeaderIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: scheme.onSurface, size: 20),
          ),
        ),
      ),
    );
  }
}

class _CartLine extends ConsumerWidget {
  const _CartLine({required this.item, required this.updating});

  final CartItem item;
  final bool updating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final product = item.product;

    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      radius: 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ProductImage(
              source: product.imageAsset,
              width: 68,
              height: 68,
            ),
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
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Remove ${product.name}',
                      child: InkWell(
                        onTap: updating
                            ? null
                            : () => ref
                                  .read(cartProvider.notifier)
                                  .remove(product),
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  Formatters.currency(product.price),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: 'Decrease quantity',
                            child: InkWell(
                              onTap: updating
                                  ? null
                                  : () => ref
                                        .read(cartProvider.notifier)
                                        .setQuantity(
                                          product,
                                          item.quantity - 1,
                                        ),
                              borderRadius: BorderRadius.circular(10),
                              child: const SizedBox(
                                width: 40,
                                height: 40,
                                child: Icon(Icons.remove_rounded, size: 18),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              '${item.quantity}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          Tooltip(
                            message: 'Increase quantity',
                            child: InkWell(
                              onTap: updating || item.quantity >= product.stock
                                  ? null
                                  : () => ref
                                        .read(cartProvider.notifier)
                                        .setQuantity(
                                          product,
                                          item.quantity + 1,
                                        ),
                              borderRadius: BorderRadius.circular(10),
                              child: const SizedBox(
                                width: 40,
                                height: 40,
                                child: Icon(Icons.add_rounded, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          Formatters.currency(item.lineTotal),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasized;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800)
        : Theme.of(context).textTheme.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Text(
          value,
          style: valueColor != null
              ? style?.copyWith(color: valueColor, fontWeight: FontWeight.w700)
              : style,
        ),
      ],
    );
  }
}
