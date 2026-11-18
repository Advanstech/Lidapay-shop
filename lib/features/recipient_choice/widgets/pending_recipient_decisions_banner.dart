import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/surface_card.dart';
import '../data/recipient_models.dart';
import '../providers.dart';

/// Recipient-side banner for incoming top-ups awaiting a choice (direct
/// delivery vs. Lida Value). Renders nothing when no pending decisions exist.
class PendingRecipientDecisionsBanner extends ConsumerStatefulWidget {
  const PendingRecipientDecisionsBanner({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  ConsumerState<PendingRecipientDecisionsBanner> createState() =>
      _PendingRecipientDecisionsBannerState();
}

class _PendingRecipientDecisionsBannerState
    extends ConsumerState<PendingRecipientDecisionsBanner> {
  Timer? _ticker;

  /// The 1s repaint exists only for the live countdown — run it only while
  /// a banner is actually on screen, never while the section is hidden.
  void _syncTicker(bool visible) {
    if (visible && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!visible && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final decisions = ref.watch(pendingRecipientDecisionsProvider);
    final now = DateTime.now();
    final active = decisions
        .where((d) => d.isPending && (d.expiresAt == null || d.expiresAt!.isAfter(now)))
        .toList();
    _syncTicker(active.isNotEmpty);
    if (active.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: widget.margin ?? const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        children: [
          for (var i = 0; i < active.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _PendingDecisionTile(decision: active[i]),
          ],
        ],
      ),
    );
  }
}

class _PendingDecisionTile extends StatelessWidget {
  const _PendingDecisionTile({required this.decision});

  final RecipientDecision decision;

  String get _countdown {
    final expiresAt = decision.expiresAt;
    if (expiresAt == null) return 'Choose now';
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Expiring';
    final mm = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sender = (decision.senderName ?? '').trim().isNotEmpty
        ? decision.senderName!.trim()
        : 'Someone';
    final amountText = decision.amount != null
        ? Formatters.money(decision.amount!, decision.currency ?? 'GHS')
        : decision.serviceLabel;

    return SurfaceCard(
      onTap: () =>
          context.push(AppRoutes.recipientDecision(decision.decisionId)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 18,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              gradient: AppColors.brandGradient,
              shape: BoxShape.circle,
            ),
            child: Icon(
              decision.serviceLabel == 'data'
                  ? Icons.wifi_rounded
                  : Icons.call_received_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$sender sent you $amountText ${decision.serviceLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap to choose direct delivery or Lida Value',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _countdown,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
