import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../data/payment_models.dart';
import '../providers.dart';

/// Shown inside a wizard once checkout has launched — while the deep-link
/// return or an app-resume recheck drives the session. A vertical stage
/// tracker keeps the user oriented through the whole
/// `awaitingCallback`/`verifying`/`crediting` window: "I've paid" re-queries
/// the saved token, "Reopen" relaunches the checkout page for an unfinished
/// momo prompt, and "Cancel" abandons only an unverified initiation.
class PaymentAwaitingPanel extends ConsumerWidget {
  const PaymentAwaitingPanel({super.key});

  static const _cardStages = [
    'Secure checkout opened',
    'Complete payment on ExpressPay',
    'Verifying payment',
    'Crediting your order',
  ];

  List<String> _momoStages(String? number) => [
    'Prompt sent to ${number ?? 'your phone'}',
    'Approve with your MoMo PIN',
    'Payment confirmed',
    'Crediting your order',
  ];

  int _stageIndex(PaymentPhase phase, bool momo) => switch (phase) {
    PaymentPhase.initiating => 0,
    PaymentPhase.awaitingCallback || PaymentPhase.verifying when momo => 1,
    PaymentPhase.awaitingCallback => 1,
    PaymentPhase.verifying => 2,
    PaymentPhase.crediting => 3,
    PaymentPhase.completed => 4,
    _ => 1,
  };

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop waiting for this payment?'),
        content: const Text(
          'If you already approved the MoMo prompt the debit may still go '
          'through. Only cancel if you declined it or never received it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep waiting'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel payment'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(paymentSessionProvider.notifier).cancelPending();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(paymentSessionProvider);
    final pending = session.pending;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final momo = pending?.method == PaymentMethod.mobileMoney;
    final stages = momo ? _momoStages(pending?.momoNumber) : _cardStages;
    // GTPay polling runs in `verifying` while the customer approves the
    // prompt — that window is "waiting on the user", not a busy spinner.
    final pollingMomo = momo && session.phase == PaymentPhase.verifying;
    final busy = session.isBusy && !pollingMomo;
    final current = _stageIndex(session.phase, momo);
    final waitingOnUser =
        session.phase == PaymentPhase.awaitingCallback || pollingMomo;
    // The network reported a failure but the debit may still reconcile —
    // the user gets a "not confirmed" state, never a silent dead end.
    final notConfirmed =
        momo &&
        session.phase == PaymentPhase.awaitingCallback &&
        const {
          'FAILED',
          'DECLINED',
          'CANCELLED',
          'CANCELED',
          'REVERSED',
        }.contains(session.providerStatus);
    // Our own approval window closed while the record was still pending —
    // the prompt almost certainly expired on the user's phone. "Check
    // status" catches a late approval; a fresh prompt is NOT offered here
    // because the old request can still debit (double-charge risk).
    final timedOut =
        momo &&
        session.phase == PaymentPhase.awaitingCallback &&
        session.providerStatus == 'TIMED_OUT';

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: amount + status copy.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            decoration: const BoxDecoration(gradient: AppColors.heroGradient),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: busy || pollingMomo
                          ? const CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            )
                          : Icon(
                              notConfirmed
                                  ? Icons.error_outline_rounded
                                  : timedOut
                                  ? Icons.timer_off_outlined
                                  : waitingOnUser
                                  ? Icons.phonelink_ring_rounded
                                  : Icons.open_in_new_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        notConfirmed
                            ? 'Payment not confirmed'
                            : timedOut
                            ? 'Prompt timed out'
                            : waitingOnUser
                            ? (momo
                                  ? 'Approve on your phone'
                                  : 'Waiting for your payment')
                            : session.phase == PaymentPhase.initiating
                            ? (momo
                                  ? 'Sending MoMo prompt…'
                                  : 'Opening secure checkout…')
                            : session.phase == PaymentPhase.crediting
                            ? 'Completing your order'
                            : 'Checking your payment',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (pending != null) ...[
                  Text(
                    Formatters.currency(pending.payAmount),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  session.message ??
                      'Approve the mobile money prompt on your phone.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),

          // Stage tracker.
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
            child: Column(
              children: [
                for (var i = 0; i < stages.length; i++)
                  _StageRow(
                    label: stages[i],
                    state: i < current
                        ? _StageState.done
                        : i == current
                        ? ((notConfirmed || timedOut) && i == 1
                              ? _StageState.failed
                              : (busy || pollingMomo
                                    ? _StageState.active
                                    : _StageState.waiting))
                        : _StageState.todo,
                    isLast: i == stages.length - 1,
                    isDark: isDark,
                  ),
              ],
            ),
          ),

          if (waitingOnUser)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  notConfirmed
                      ? 'If you entered your PIN and the debit went through, '
                            'tap “Check status”. If it was declined or the '
                            'prompt timed out, send a new prompt — each '
                            'attempt only debits once.'
                      : timedOut
                      ? 'Check for a pending approval on your phone — '
                            'MTN: *170# → My Approvals, Telecel: *110#, '
                            'AirtelTigo: *110#. If it’s there, approve it '
                            'then tap “Check status”. Otherwise cancel and '
                            'start again — a new prompt is only safe after '
                            'this one is cancelled.'
                      : momo
                      ? 'No prompt? Dial your MoMo menu and approve the pending '
                            'payment — MTN: *170# → My Approvals, Telecel: '
                            '*110#, AirtelTigo: *110#.'
                      : 'Finished on ExpressPay? You’ll be brought back here '
                            'automatically. If not, return to Lidapay and tap '
                            '“I’ve paid”.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),

          // Actions.
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
            child: Column(
              children: [
                Row(
                  children: [
                    if (!busy && !momo) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => ref
                              .read(paymentSessionProvider.notifier)
                              .reopenCheckout(),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: AppColors.primary,
                              width: 1.3,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Reopen',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: busy || pollingMomo
                              ? null
                              : AppColors.brandGradient,
                          color: busy || pollingMomo
                              ? (isDark
                                    ? AppColors.darkInput
                                    : const Color(0xFFE5E5EA))
                              : null,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: busy || pollingMomo
                                ? null
                                : () => ref
                                      .read(paymentSessionProvider.notifier)
                                      .recheck(),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (busy || pollingMomo)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  else
                                    const Icon(
                                      Icons.check_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  const SizedBox(width: 8),
                                  Text(
                                    pollingMomo
                                        ? 'Checking…'
                                        : busy
                                        ? 'Verifying…'
                                        : notConfirmed || timedOut
                                        ? 'Check status'
                                        : (momo ? "I've approved" : "I've paid"),
                                    style: TextStyle(
                                      color: busy || pollingMomo
                                          ? scheme.onSurfaceVariant
                                          : Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (notConfirmed && !busy)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: OutlinedButton.icon(
                      onPressed: () => ref
                          .read(paymentSessionProvider.notifier)
                          .retryMobileMoney(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: AppColors.primary,
                          width: 1.3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        minimumSize: const Size.fromHeight(0),
                      ),
                      icon: const Icon(
                        Icons.phonelink_ring_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      label: const Text(
                        'Send a new prompt',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                if (!busy && !pollingMomo)
                  TextButton(
                    onPressed: () => momo
                        ? _confirmCancel(context, ref)
                        : ref
                              .read(paymentSessionProvider.notifier)
                              .cancelPending(),
                    child: Text(
                      notConfirmed
                          ? 'Cancel & choose another method'
                          : timedOut
                          ? 'Cancel & try again'
                          : 'Cancel this payment',
                      style: TextStyle(color: scheme.error, fontSize: 13),
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

enum _StageState { todo, waiting, active, done, failed }

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.state,
    required this.isLast,
    required this.isDark,
  });

  final String label;
  final _StageState state;
  final bool isLast;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = state == _StageState.done;
    final active = state == _StageState.active;
    final waiting = state == _StageState.waiting;
    final failed = state == _StageState.failed;

    return IntrinsicHeight(
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: done || active ? AppColors.brandGradient : null,
                    color: failed
                        ? AppColors.error
                        : done || active
                        ? null
                        : (isDark ? Colors.white10 : const Color(0xFFEDEAF3)),
                    border: Border.all(
                      color: done || active || failed
                          ? Colors.transparent
                          : (isDark ? Colors.white24 : const Color(0xFFD9D6E4)),
                      width: 1.4,
                    ),
                  ),
                  child: failed
                      ? const Icon(
                          Icons.close_rounded,
                          size: 13,
                          color: Colors.white,
                        )
                      : done
                      ? const Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: Colors.white,
                        )
                      : active
                      ? const Padding(
                          padding: EdgeInsets.all(5),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : waiting
                      ? Container(
                          margin: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary,
                          ),
                        )
                      : null,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: done
                            ? AppColors.primary
                            : (isDark
                                  ? Colors.white12
                                  : const Color(0xFFE3E0EC)),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 10 : 16),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: active || waiting || done || failed
                      ? FontWeight.w800
                      : FontWeight.w500,
                  color: failed
                      ? scheme.error
                      : done || active || waiting
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
