import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../auth/providers.dart';
import '../../notifications/providers.dart';
import '../../services/providers.dart';
import '../data/recipient_models.dart';
import '../providers.dart';

/// Recipient-facing decision screen — the person the top-up was sent to
/// chooses direct delivery or Lida Value before the window closes. The
/// countdown is display-only; the backend owns resolution and the top-up
/// status tracker is the settlement authority.
class RecipientDecisionScreen extends ConsumerStatefulWidget {
  const RecipientDecisionScreen({super.key, required this.decisionId});

  final String decisionId;

  @override
  ConsumerState<RecipientDecisionScreen> createState() =>
      _RecipientDecisionScreenState();
}

class _RecipientDecisionScreenState
    extends ConsumerState<RecipientDecisionScreen> {
  Timer? _ticker;
  Duration _remaining = Duration.zero;
  bool _submitting = false;
  RecipientChoice? _submitted;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(readNotificationsProvider.notifier)
          .markRead(
            'decision_${widget.decisionId}',
            relatedKeys: ['decision|${widget.decisionId}'],
          );
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    final decision = ref
        .read(recipientDecisionProvider(widget.decisionId))
        .valueOrNull;
    if (!mounted) return;
    setState(() {
      _remaining =
          decision?.expiresAt?.difference(DateTime.now()) ?? Duration.zero;
      if (_remaining.isNegative) _remaining = Duration.zero;
    });
  }

  /// The decision endpoint's `recipientPhone` is authoritative — only the
  /// account it was issued for may answer it.
  bool _recipientMatches(RecipientDecision decision) {
    final intended = _digits(decision.recipientPhone);
    if (intended.isEmpty) return true;
    final mine = _digits(ref.read(authSessionProvider)?.user.phoneNumber);
    if (mine.isEmpty) return true;
    return intended == mine ||
        intended == '233$mine' ||
        mine == '233${intended.replaceFirst(RegExp('^0'), '')}';
  }

  static String _digits(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\D'), '');

  Future<void> _respond(
    RecipientDecision decision,
    RecipientChoice choice,
  ) async {
    if (_submitting) return;
    final confirmed = await _confirm(choice);
    if (confirmed != true || !mounted) return;
    setState(() {
      _submitting = true;
      _submitted = choice;
      _error = null;
    });
    try {
      await ref
          .read(recipientChoiceRepositoryProvider)
          .respondToDecision(
            decisionId: widget.decisionId,
            choice: choice,
            idempotencyKey: newDecisionIdempotencyKey(
              widget.decisionId,
              choice,
            ),
          );
      ref.invalidate(recipientDecisionProvider(widget.decisionId));
    } on ApiException catch (e) {
      setState(() {
        _submitting = false;
        _submitted = null;
        _error = e.message;
      });
    } catch (_) {
      setState(() {
        _submitting = false;
        _submitted = null;
        _error = 'Could not submit your choice. Please try again.';
      });
    }
  }

  Future<bool?> _confirm(RecipientChoice choice) {
    final isValue = choice == RecipientChoice.lidaValue;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isValue ? 'Save to Lida Value?' : 'Accept direct top-up?'),
        content: Text(
          isValue
              ? 'The value will be stored in your Lida Value wallet — you can '
                    'use, send, sell or convert it later.'
              : 'The top-up will be delivered straight to your phone now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final decisionAsync = ref.watch(
      recipientDecisionProvider(widget.decisionId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Incoming top-up')),
      body: SafeArea(
        child: decisionAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorView(
            onRetry: () =>
                ref.invalidate(recipientDecisionProvider(widget.decisionId)),
          ),
          data: (decision) {
            // Once a choice lands, settlement is tracked through the top-up
            // status — the respond response alone is not the final word.
            final topupId = decision.topupOrderId.isNotEmpty
                ? decision.topupOrderId
                : null;
            final tracker = topupId == null
                ? const AsyncValue<TopupOrderStatus>.loading()
                : ref.watch(topupStatusTrackerProvider(topupId));
            final topup = tracker.valueOrNull;

            return _DecisionBody(
              decision: decision,
              topup: topup,
              remaining: _remaining,
              submitting: _submitting,
              submitted: _submitted,
              error: _error,
              recipientMatches: _recipientMatches(decision),
              onChoose: (choice) => _respond(decision, choice),
              onSettled: (status) {
                // Keep the wallet fresh whichever way it landed.
                ref.invalidate(lidaValueProvider);
                ref.invalidate(lidaPointsProvider);
              },
            );
          },
        ),
      ),
    );
  }
}

class _DecisionBody extends StatelessWidget {
  const _DecisionBody({
    required this.decision,
    required this.topup,
    required this.remaining,
    required this.submitting,
    required this.submitted,
    required this.error,
    required this.recipientMatches,
    required this.onChoose,
    required this.onSettled,
  });

  final RecipientDecision decision;
  final TopupOrderStatus? topup;
  final Duration remaining;
  final bool submitting;
  final RecipientChoice? submitted;
  final String? error;
  final bool recipientMatches;
  final ValueChanged<RecipientChoice> onChoose;
  final ValueChanged<TopupOrderStatus> onSettled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkSurface : Colors.white;

    // Terminal states — server truth wins over the countdown.
    if (topup?.isTerminal == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onSettled(topup!));
      return _OutcomeView(status: topup!, serviceLabel: decision.serviceLabel);
    }
    if (decision.isResolved) {
      return _ResolvedDecisionView(decision: decision);
    }
    if (decision.status == DecisionStatus.expired && topup == null) {
      return const _ExpiredView();
    }

    final amount = decision.amount;
    final sender = decision.senderName ?? 'A Lidapay user';
    final windowClosed = remaining == Duration.zero;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              gradient: AppColors.brandGradient,
              shape: BoxShape.circle,
            ),
            child: Icon(
              decision.serviceLabel == 'data'
                  ? Icons.wifi_rounded
                  : Icons.call_rounded,
              size: 42,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          amount != null
              ? '$sender sent you ${Formatters.money(amount, decision.currency ?? 'GHS')} ${decision.serviceLabel}'
              : '$sender sent you a ${decision.serviceLabel} top-up',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose how you want to receive it.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5),
        ),
        const SizedBox(height: 24),
        _CountdownCard(
          remaining: remaining,
          expired: windowClosed || decision.status == DecisionStatus.expired,
          submitting: submitting,
        ),
        const SizedBox(height: 20),
        if (!recipientMatches)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'This top-up was issued for a different phone number. Sign in '
              'with that account to respond.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        _ChoiceCard(
          icon: Icons.bolt_rounded,
          tint: AppColors.success,
          cardBg: cardBg,
          title: 'Deliver to my phone',
          subtitle:
              'Get the ${decision.serviceLabel} credited to '
              '${decision.recipientPhone ?? 'your number'} right away.',
          loading: submitting && submitted == RecipientChoice.direct,
          enabled: recipientMatches && !submitting && !windowClosed,
          onTap: () => onChoose(RecipientChoice.direct),
        ),
        const SizedBox(height: 14),
        _ChoiceCard(
          icon: Icons.diamond_rounded,
          tint: AppColors.violet,
          cardBg: cardBg,
          title: 'Save to Lida Value',
          subtitle:
              'Keep it in your Lida Value wallet — use, send, sell or '
              'convert it whenever you like.',
          loading: submitting && submitted == RecipientChoice.lidaValue,
          enabled: recipientMatches && !submitting && !windowClosed,
          onTap: () => onChoose(RecipientChoice.lidaValue),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (windowClosed || submitting) ...[
          const SizedBox(height: 18),
          Text(
            submitting
                ? 'Submitting your choice — confirming with the server…'
                : 'The window closed. The value will default to your Lida '
                      'Value wallet — confirming…',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),
        ],
      ],
    );
  }
}

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({
    required this.remaining,
    required this.expired,
    required this.submitting,
  });

  final Duration remaining;
  final bool expired;
  final bool submitting;

  @override
  Widget build(BuildContext context) {
    final mm = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    final color = expired
        ? AppColors.error
        : remaining.inSeconds < 60
        ? AppColors.warning
        : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer_outlined, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              expired
                  ? 'Response window closed'
                  : submitting
                  ? 'Processing your choice'
                  : 'Choose within $mm:$ss — then it defaults to Lida Value',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.tint,
    required this.cardBg,
    required this.title,
    required this.subtitle,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final Color cardBg;
  final String title;
  final String subtitle;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: tint.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: tint),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.chevron_right_rounded, color: tint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutcomeView extends StatelessWidget {
  const _OutcomeView({required this.status, required this.serviceLabel});

  final TopupOrderStatus status;
  final String serviceLabel;

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, body) = status.isDeliveredToLidaValue
        ? (
            Icons.diamond_rounded,
            AppColors.violet,
            'Saved to your Lida Value',
            'The $serviceLabel value is in your wallet — use, send, sell or '
                'convert it whenever you like.',
          )
        : status.isDeliveredDirect
        ? (
            Icons.check_circle_rounded,
            AppColors.success,
            'Delivered to your phone',
            'The $serviceLabel has been credited to '
                '${status.recipientPhone ?? 'your number'}.',
          )
        : (
            Icons.error_outline_rounded,
            AppColors.error,
            'Delivery did not complete',
            status.failedReason ??
                'The top-up could not be delivered. The sender has been '
                    'notified.',
          );
    return Center(
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
              child: Icon(icon, size: 52, color: color),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 28),
            AppButton(
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResolvedDecisionView extends StatelessWidget {
  const _ResolvedDecisionView({required this.decision});

  final RecipientDecision decision;

  @override
  Widget build(BuildContext context) {
    final saved = decision.savedToLidaValue;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              saved ? Icons.diamond_rounded : Icons.check_circle_rounded,
              size: 64,
              color: saved ? AppColors.violet : AppColors.success,
            ),
            const SizedBox(height: 18),
            Text(
              saved ? 'Already saved to Lida Value' : 'Already delivered',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              decision.resolvedSource == 'TIMEOUT'
                  ? 'The response window expired and the default was applied.'
                  : 'This decision was already answered.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpiredView extends StatelessWidget {
  const _ExpiredView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.timer_off_outlined,
              size: 64,
              color: AppColors.warning,
            ),
            const SizedBox(height: 18),
            Text(
              'Response window closed',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text(
              'The value defaults to your Lida Value wallet. Pull to '
              'refresh in a moment to see the credit.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 56, color: AppColors.error),
          const SizedBox(height: 14),
          const Text('Could not load this top-up request.'),
          const SizedBox(height: 16),
          AppButton(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}
