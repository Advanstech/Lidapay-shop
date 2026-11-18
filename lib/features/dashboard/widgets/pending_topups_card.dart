import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/surface_card.dart';
import '../../recipient_choice/data/recipient_models.dart';
import '../../recipient_choice/screens/pending_topup_screen.dart';
import '../../services/data/service_models.dart';
import '../providers.dart';

/// Dashboard surface for top-ups parked behind a recipient decision — one
/// row per in-flight `decision_pending` ledger entry showing who it's
/// waiting on, the amount and a live countdown to the window closing.
/// Tapping reopens the full waiting screen so the sender can watch the
/// same countdown ring and leave again without cancelling anything.
/// Renders nothing when no top-up is waiting.
class PendingTopupsCard extends ConsumerStatefulWidget {
  const PendingTopupsCard({super.key});

  @override
  ConsumerState<PendingTopupsCard> createState() => _PendingTopupsCardState();
}

class _PendingTopupsCardState extends ConsumerState<PendingTopupsCard> {
  Timer? _ticker;

  /// The 1s repaint exists only for the live countdown — run it only while
  /// a card is actually on screen, never while the section is hidden.
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
    final statuses = ref.watch(pendingRecipientTopupsProvider).valueOrNull;
    final visible = statuses != null && statuses.isNotEmpty;
    _syncTicker(visible);
    if (!visible) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final status in statuses) ...[
            _PendingTopupTile(status: status),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _PendingTopupTile extends StatelessWidget {
  const _PendingTopupTile({required this.status});

  final TopupOrderStatus status;

  String get _recipient =>
      status.recipientPhone ??
      status.decision?.recipientPhone ??
      'the recipient';

  String get _serviceLabel => status.serviceLabel;

  IconData get _icon => _serviceLabel == 'data'
      ? Icons.wifi_tethering_rounded
      : Icons.phone_iphone_rounded;

  String get _amountLabel {
    final amount = status.amount ?? status.decision?.amount;
    if (amount == null) return _serviceLabel;
    return Formatters.money(amount, status.decision?.currency ?? 'GHS');
  }

  /// mm:ss left in the decision window, or a state word once it's gone.
  String get _countdown {
    final expiresAt = status.decision?.expiresAt;
    if (expiresAt == null) return 'waiting';
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return 'settling';
    final mm = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  void _openWaitingScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PendingTopupScreen(
          pending: PendingTopup(
            topupOrderId: status.topupOrderId,
            decisionId: status.decision?.decisionId,
            expiresAt: status.decision?.expiresAt,
          ),
          amountLabel: _amountLabel,
          recipientLabel: _recipient,
          serviceLabel: _serviceLabel,
          icon: _icon,
          onDone: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.warning;

    return SurfaceCard(
      onTap: () => _openWaitingScreen(context),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 18,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.22),
                  accent.withValues(alpha: 0.10),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: accent.withValues(alpha: isDark ? 0.35 : 0.25),
              ),
            ),
            child: Icon(_icon, size: 20, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waiting for $_recipient',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_amountLabel $_serviceLabel · tap to watch',
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
              color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _countdown,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
