import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../data/dashboard_models.dart';

/// Compact status pill for transaction rows.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final TransactionStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      TransactionStatus.success => (AppColors.success, 'Success'),
      TransactionStatus.pending => (AppColors.warning, 'Pending'),
      TransactionStatus.failed => (AppColors.error, 'Failed'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Flat transaction entry — designed to sit inside [SurfaceCard]s on the
/// dashboard and history lists (dividers between rows handled by the parent).
class TransactionRow extends StatelessWidget {
  const TransactionRow({super.key, required this.transaction, this.onTap});

  final Transaction transaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final network = _networkOf(transaction);
    final isCredit = transaction.isMoneyIn;

    final amountColor = switch (transaction.status) {
      TransactionStatus.failed => scheme.onSurfaceVariant,
      _ when isCredit => AppColors.success,
      _ => scheme.onSurface,
    };

    final title = transaction.description.isEmpty
        ? transaction.type.label
        : transaction.description;
    final subtitle =
        '${Formatters.dateTime(transaction.createdAt)}${transaction.counterparty != null ? ' · ${transaction.counterparty}' : ''}';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            network != null
                ? Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: network.$2,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      network.$1,
                      style: TextStyle(
                        color: network.$3,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  )
                : Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: _iconTint(transaction).withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _icon(transaction),
                      size: 22,
                      color: _iconTint(transaction),
                    ),
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${isCredit ? '+' : '−'}${Formatters.money(transaction.amount, transaction.currency)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: amountColor,
                  ),
                ),
                if (transaction.status != TransactionStatus.success) ...[
                  const SizedBox(height: 3),
                  Text(
                    transaction.status == TransactionStatus.pending
                        ? 'Pending'
                        : 'Failed',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: transaction.status == TransactionStatus.pending
                          ? AppColors.warning
                          : AppColors.error,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static IconData _icon(Transaction t) => switch (t.type) {
    TransactionType.airtime => Icons.call_rounded,
    TransactionType.data => Icons.wifi_tethering_rounded,
    TransactionType.shopOrder => Icons.shopping_bag_outlined,
    TransactionType.lidaValue => Icons.diamond_outlined,
    TransactionType.walletTopUp => Icons.add_card_rounded,
    TransactionType.other => Icons.receipt_long_rounded,
  };

  static Color _iconTint(Transaction t) => switch (t.type) {
    TransactionType.airtime => AppColors.primary,
    TransactionType.data => AppColors.violet,
    TransactionType.shopOrder => AppColors.primary,
    TransactionType.lidaValue => AppColors.warning,
    TransactionType.walletTopUp => AppColors.violet,
    TransactionType.other => AppColors.ink,
  };

  /// Ghanaian network avatars (solid brand chips with initials) for
  /// airtime/data rows; null → fall back to the type icon.
  static (String, Color, Color)? _networkOf(Transaction t) {
    if (t.type != TransactionType.airtime && t.type != TransactionType.data) {
      return null;
    }
    final text = '${t.description} ${t.counterparty ?? ''}'.toUpperCase();
    if (text.contains('MTN')) {
      return ('MTN', const Color(0xFFFFCC00), AppColors.ink);
    }
    if (text.contains('TELECEL') || text.contains('VODAFONE')) {
      return ('TC', const Color(0xFFE60000), Colors.white);
    }
    if (text.contains('AIRTEL') || text.contains('TIGO')) {
      return ('AT', const Color(0xFF0066B3), Colors.white);
    }
    if (RegExp(r'\bGLO\b').hasMatch(text)) {
      return ('GLO', const Color(0xFF00A651), Colors.white);
    }
    return null;
  }
}
