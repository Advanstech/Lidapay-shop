import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../dashboard/providers.dart';
import '../../history/providers.dart';
import '../../recipient_choice/screens/pending_topup_screen.dart';
import '../../services/data/service_models.dart';
import '../../services/providers.dart';
import '../../services/widgets/service_receipt_screen.dart';
import '../../shop/data/shop_models.dart';
import '../../shop/providers.dart';
import '../../shop/screens/checkout_success_screen.dart';
import '../data/pending_payment.dart';
import '../providers.dart';
import '../widgets/payment_awaiting_panel.dart';

/// Root-level target for `lidapay://` payment returns. It consumes the
/// callback's hint params, hands verification to the shared
/// [paymentSessionProvider], and renders the outcome itself — so a cold
/// start lands on a complete receipt without the wizard on the stack.
class PaymentReturnScreen extends ConsumerStatefulWidget {
  const PaymentReturnScreen({
    super.key,
    this.status,
    this.orderId,
    this.hasCallbackToken = false,
    this.errorMessage,
  });

  final String? status;
  final String? orderId;
  final bool hasCallbackToken;
  final String? errorMessage;

  @override
  ConsumerState<PaymentReturnScreen> createState() =>
      _PaymentReturnScreenState();
}

class _PaymentReturnScreenState extends ConsumerState<PaymentReturnScreen> {
  ServiceReceipt? _resolvedReceipt;
  PendingPayment? _resolvedPending;
  ShopOrder? _resolvedOrder;
  String? _resolvedShopOrderNumber;
  String? _resolvedFailure;
  bool _loadingShopOrder = false;

  @override
  void initState() {
    super.initState();
    _resolvedPending = ref.read(paymentSessionProvider).pending;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(paymentSessionProvider.notifier)
          .handleReturn(
            status: widget.status,
            orderId: widget.orderId,
            token: widget.hasCallbackToken ? 'present' : null,
          );
    });
  }

  void _invalidateFeeds() {
    ref.invalidate(historyProvider);
    ref.invalidate(historyAnalyticsProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(walletSummaryProvider);
    ref.invalidate(lidaPointsProvider);
    ref.invalidate(lidaValueProvider);
    ref.invalidate(userOrdersProvider);
    ref.invalidate(ordersControllerProvider);
  }

  Future<void> _fetchShopOrder(
    PaymentSessionState session,
    PendingPayment? pending,
  ) async {
    if (_loadingShopOrder) return;
    _loadingShopOrder = true;
    final repo = ref.read(shopRepositoryProvider);
    final orderId = pending?.params['orderId']?.toString();
    final orderNumber = session.shopOrderNumber;
    ShopOrder? fetched;
    try {
      if (orderId != null && orderId.isNotEmpty) {
        fetched = await repo.getOrder(orderId);
      }
      if (fetched == null && orderNumber != null && orderNumber.isNotEmpty) {
        fetched = await repo.getOrderByNumber(orderNumber);
      }
    } catch (_) {
      // Fall back cleanly to cached/saved order fields below.
    }
    if (!mounted) return;
    setState(() {
      if (fetched != null) {
        _resolvedOrder = fetched;
      }
      _loadingShopOrder = false;
    });
  }

  void _finishToHome() {
    ref.read(paymentSessionProvider.notifier).reset();
    context.go(AppRoutes.home);
  }

  void _continueAnotherTransaction(bool isData) {
    ref.read(paymentSessionProvider.notifier).reset();
    context.go(isData ? AppRoutes.data : AppRoutes.airtime);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PaymentSessionState>(paymentSessionProvider, (prev, next) {
      if (!mounted) return;
      if (next.pending != null) {
        _resolvedPending = next.pending;
      }
      if (next.phase == PaymentPhase.completed) {
        _invalidateFeeds();
        setState(() {
          _resolvedReceipt ??= next.receipt;
          _resolvedShopOrderNumber ??= next.shopOrderNumber;
          if (next.receipt == null && _resolvedOrder == null) {
            final lastOrder = ref.read(lastOrderProvider);
            if (lastOrder != null &&
                (next.shopOrderNumber == null ||
                    lastOrder.reference == next.shopOrderNumber)) {
              _resolvedOrder = lastOrder;
            }
          }
        });
        if (next.receipt == null) {
          unawaited(_fetchShopOrder(next, _resolvedPending));
        }
      } else if (next.phase == PaymentPhase.failed) {
        setState(() {
          _resolvedFailure ??=
              widget.errorMessage ??
              next.message ??
              'The payment could not be confirmed.';
        });
      }
    });

    final session = ref.watch(paymentSessionProvider);
    final receipt = _resolvedReceipt ?? session.receipt;
    final pending = _resolvedPending ?? session.pending;
    final shopOrderNumber = _resolvedShopOrderNumber ?? session.shopOrderNumber;

    // Delivery confirmed — show the real receipt.
    if (receipt != null) {
      if (receipt.pendingTopup case final pendingTopup?) {
        final isData =
            pending?.kind == PendingPaymentKind.ghanaData ||
            pending?.kind == PendingPaymentKind.globalData;
        final amount = pending?.payAmount ?? 0;
        final currency = pending?.payCurrency ?? 'GHS';
        return PendingTopupScreen(
          pending: pendingTopup,
          amountLabel: currency == 'GHS'
              ? Formatters.currency(amount)
              : '$currency ${amount.toStringAsFixed(2)}',
          recipientLabel: pending?.params['recipientNumber']?.toString() ?? '',
          serviceLabel: isData ? 'data bundle' : 'airtime',
          icon: isData ? Icons.wifi_rounded : Icons.call_rounded,
          onDone: _finishToHome,
          onNewTransaction: () => _continueAnotherTransaction(isData),
        );
      }
      return ServiceReceiptScreen(
        receipt: receipt,
        icon: Icons.payments_rounded,
        onDone: _finishToHome,
      );
    }

    if (session.phase == PaymentPhase.completed ||
        shopOrderNumber != null ||
        _resolvedOrder != null) {
      final order =
          _resolvedOrder ??
          ref.watch(lastOrderProvider) ??
          ShopOrder(
            id:
                pending?.params['orderId']?.toString() ??
                shopOrderNumber ??
                'order',
            reference: shopOrderNumber ?? 'ORD',
            itemCount: 1,
            total: pending?.payAmount ?? 0,
            currency: pending?.payCurrency ?? 'GHS',
            placedAt: DateTime.now(),
            paymentStatus: 'paid',
            status: 'processing',
          );
      return CheckoutSuccessScreen(order: order);
    }

    final failureMessage =
        _resolvedFailure ??
        (session.phase == PaymentPhase.failed
            ? (widget.errorMessage ??
                  session.message ??
                  'The payment could not be confirmed.')
            : null);
    if (failureMessage != null) {
      return _OutcomeScaffold(
        success: false,
        title: 'Payment not completed',
        message: failureMessage,
        actionLabel: 'Back',
        onAction: () {
          ref.read(paymentSessionProvider.notifier).reset();
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(AppRoutes.home);
          }
        },
      );
    }

    // verifying / crediting / awaitingCallback — the awaiting panel gives a
    // manual recheck once the query loop settles back to awaiting.
    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: session.phase == PaymentPhase.awaitingCallback
                ? const PaymentAwaitingPanel()
                : const _VerifyingView(),
          ),
        ),
      ),
    );
  }
}

class _VerifyingView extends ConsumerWidget {
  const _VerifyingView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(paymentSessionProvider);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(strokeWidth: 4),
        ),
        const SizedBox(height: 20),
        Text(
          session.phase == PaymentPhase.crediting
              ? 'Completing your order'
              : 'Verifying payment',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          session.message ?? 'Checking the payment status…',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _OutcomeScaffold extends StatelessWidget {
  const _OutcomeScaffold({
    required this.success,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final bool success;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = success ? const Color(0xFF16A34A) : scheme.error;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    success ? Icons.check_circle_rounded : Icons.error_rounded,
                    size: 56,
                    color: color,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onAction,
                    child: Text(actionLabel),
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
