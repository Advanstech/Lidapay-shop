import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../services/widgets/service_receipt_screen.dart';
import '../../shop/data/shop_models.dart';
import '../../shop/providers.dart';
import '../../shop/screens/checkout_success_screen.dart';
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
  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(paymentSessionProvider);

    // Delivery confirmed — show the real receipt. For shop payments the
    // order list is the destination.
    if (session.phase == PaymentPhase.completed) {
      final receipt = session.receipt;
      if (receipt != null) {
        return ServiceReceiptScreen(
          receipt: receipt,
          icon: Icons.payments_rounded,
          onDone: () => context.go(AppRoutes.home),
        );
      }
      final lastOrder = ref.watch(lastOrderProvider);
      final order =
          lastOrder ??
          ShopOrder(
            id: session.shopOrderNumber ?? 'order',
            reference: session.shopOrderNumber ?? 'ORD',
            itemCount: 1,
            total: session.pending?.payAmount ?? 0,
            currency: session.pending?.payCurrency ?? 'GHS',
            placedAt: DateTime.now(),
            paymentStatus: 'paid',
            status: 'processing',
          );
      return CheckoutSuccessScreen(order: order);
    }

    if (session.phase == PaymentPhase.failed) {
      return _OutcomeScaffold(
        success: false,
        title: 'Payment not completed',
        message:
            widget.errorMessage ??
            session.message ??
            'The payment could not be confirmed.',
        actionLabel: 'Back',
        onAction: () =>
            context.canPop() ? context.pop() : context.go(AppRoutes.home),
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
