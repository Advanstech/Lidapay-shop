import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../dashboard/data/dashboard_models.dart';

/// Opens the full-height transaction receipt used by both the dashboard
/// Recent activity feed and the Activity tab.
void showTransactionDetails(
  BuildContext context,
  Transaction transaction, {
  required String userPhone,
}) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.96,
      child: TransactionDetailsSheet(
        transaction: transaction,
        userPhone: userPhone,
      ),
    ),
  );
}

class TransactionDetailsSheet extends StatelessWidget {
  const TransactionDetailsSheet({
    super.key,
    required this.transaction,
    required this.userPhone,
  });

  final Transaction transaction;
  final String userPhone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final surfaceBg = isDark ? AppColors.darkScaffold : const Color(0xFFF6F6F9);
    final cardBg = isDark ? AppColors.darkSurface : Colors.white;
    final localDate = transaction.createdAt.toLocal();
    final dateFormatted = DateFormat('MMM d, yyyy').format(localDate);
    final timeFormatted = DateFormat('hh:mm a').format(localDate);
    final amountFormatted = Formatters.money(
      transaction.amount,
      transaction.currency,
    );
    final recipient = transaction.counterparty?.isNotEmpty == true
        ? transaction.counterparty!
        : (transaction.description.isNotEmpty
              ? transaction.description
              : transaction.type.label);
    final typeLabel = switch (transaction.type) {
      TransactionType.airtime => 'Airtime Top-up',
      TransactionType.data => 'Data Bundle',
      TransactionType.shopOrder => 'Shop Order',
      TransactionType.lidaValue => 'Lida Value',
      TransactionType.walletTopUp => 'Wallet Top-up',
      TransactionType.other => 'Transfer',
    };
    final (statusColor, statusBg, statusLabel) = switch (transaction.status) {
      TransactionStatus.success => (
        const Color(0xFF33B457),
        const Color(0xFFEAF8EE),
        'COMPLETED',
      ),
      TransactionStatus.pending => (
        AppColors.warning,
        const Color(0xFFFFF4E5),
        'PENDING',
      ),
      TransactionStatus.failed => (
        AppColors.error,
        const Color(0xFFFDECEC),
        'FAILED',
      ),
    };

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Material(
        color: surfaceBg,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              decoration: const BoxDecoration(gradient: AppColors.heroGradient),
              child: Column(
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Transaction Details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Share.share(
                            'Lidapay Receipt · $typeLabel · $amountFormatted · Ref: ${transaction.reference}',
                          );
                        },
                        icon: const Icon(
                          Icons.share_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.receipt_long_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            transaction.reference.isEmpty
                                ? 'TRX-${transaction.id}'
                                : transaction.reference,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          if (!isDark)
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Transfer Journey',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurface,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? statusColor.withValues(alpha: 0.16)
                                      : statusBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Column(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF33B457),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Expanded(
                                      child: Container(
                                        width: 2,
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        color: const Color(0xFF33B457)
                                            .withValues(alpha: 0.35),
                                      ),
                                    ),
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF33B457)
                                            .withValues(alpha: 0.55),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'From',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        userPhone,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Lidapay Wallet',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Text(
                                        'To',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        recipient,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        typeLabel,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _JourneyInfoBox(
                                label: 'Type',
                                value: typeLabel,
                                isDark: isDark,
                              ),
                              _JourneyInfoBox(
                                label: 'Date',
                                value: dateFormatted,
                                isDark: isDark,
                              ),
                              _JourneyInfoBox(
                                label: 'Time',
                                value: timeFormatted,
                                isDark: isDark,
                              ),
                              _JourneyInfoBox(
                                label: 'Amount',
                                value: amountFormatted,
                                isDark: isDark,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          if (!isDark)
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? statusColor.withValues(alpha: 0.16)
                                  : statusBg,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              transaction.status == TransactionStatus.failed
                                  ? Icons.cancel_rounded
                                  : (transaction.status ==
                                            TransactionStatus.pending
                                        ? Icons.schedule_rounded
                                        : Icons.check_circle_rounded),
                              color: statusColor,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Status',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                statusLabel,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyInfoBox extends StatelessWidget {
  const _JourneyInfoBox({
    required this.label,
    required this.value,
    required this.isDark,
  });

  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.primary.withValues(alpha: 0.12)
            : const Color(0xFFFCF1F5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}
