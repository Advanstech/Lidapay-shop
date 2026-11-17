import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/sticky_header.dart';
import '../../services/data/service_models.dart';
import '../../services/providers.dart';

class LidaValueScreen extends ConsumerWidget {
  const LidaValueScreen({super.key});

  static bool _isCreditItem(ServiceReceipt item) {
    final text = '${item.title} ${item.message}'.toUpperCase();
    return item.isCredit ??
        (text.contains('SAVE') ||
            text.contains('ACCEPT') ||
            text.contains('CREDIT') ||
            text.contains('EARN') ||
            text.contains('RECEIVE'));
  }

  static String _codeLabel(ServiceReceipt item) {
    final raw = item.title.trim();
    if (raw.contains('_')) return raw.toUpperCase();
    final upper = raw.toUpperCase();
    if (upper.contains('SAVE') || upper.contains('ACCEPT')) {
      return 'SAVE_FROM_PURCHASE';
    }
    if (upper.contains('SEND')) return 'USE_SEND';
    if (upper.contains('SELL')) return 'USE_SELL';
    if (upper.contains('CONVERT')) return 'USE_CONVERT';
    if (upper.contains('USE')) return 'USE_USE';
    return upper.replaceAll(RegExp(r'\s+'), '_');
  }

  static String _friendlyLabel(ServiceReceipt item) {
    final code = _codeLabel(item);
    return code
        .split('_')
        .where((p) => p.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(lidaValueProvider);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkSurface : Colors.white;

    return Scaffold(
      body: value.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: AppSkeletonScreen(),
        ),
        error: (error, _) => ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(lidaValueProvider),
        ),
        data: (wallet) {
          final previewHistory = wallet.history.take(5).toList();
          final topInset = MediaQuery.paddingOf(context).top;
          final scaffoldBg = isDark
              ? AppColors.darkScaffold
              : AppColors.lightScaffold;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(lidaValueProvider);
              await ref.read(lidaValueProvider.future);
            },
            edgeOffset: topInset + 68,
            child: CustomScrollView(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: StickySliverHeaderDelegate(
                    height: topInset + 68,
                    builder: (context, isStuck) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: scaffoldBg,
                        boxShadow: isStuck
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: isDark ? 0.28 : 0.06,
                                  ),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20, topInset + 10, 20, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white10
                                      : const Color(0xFFECEAF2),
                                ),
                                boxShadow: [
                                  if (!isDark)
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.04,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                ],
                              ),
                              child: IconButton(
                                icon: Icon(
                                  Icons.arrow_back_rounded,
                                  color: scheme.onSurface,
                                  size: 22,
                                ),
                                tooltip: 'Back',
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ),
                            const Expanded(
                              child: Center(
                                child: Text(
                                  'Lida Value',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: AppColors.heroGradient,
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: AppShadows.glow(
                              AppColors.primary,
                              alpha: isDark ? 0.28 : 0.22,
                              blur: 28,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Current Lida Value',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'Available value',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.65,
                                      ),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    wallet.balance.toStringAsFixed(2),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 36,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.8,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'LV',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              if (wallet.pending > 0) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${wallet.pending.toStringAsFixed(2)} LV pending recipient decisions',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: _LidaValueActionPill(
                                icon: Icons.bolt_rounded,
                                label: 'Use',
                                isDark: isDark,
                                onTap: () =>
                                    _openTopupChooser(context, forSelf: true),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _LidaValueActionPill(
                                icon: Icons.send_rounded,
                                label: 'Send',
                                isDark: isDark,
                                onTap: () =>
                                    _openTopupChooser(context, forSelf: false),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _LidaValueActionPill(
                                icon: Icons.autorenew_rounded,
                                label: 'Sell',
                                isDark: isDark,
                                onTap: () => _openActionSheet(
                                  context,
                                  ref,
                                  action: 'sell',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _LidaValueActionPill(
                                icon: Icons.account_balance_rounded,
                                label: 'Convert',
                                isDark: isDark,
                                onTap: () => _openActionSheet(
                                  context,
                                  ref,
                                  action: 'convert',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'History',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 19,
                              ),
                        ),
                        const SizedBox(height: 14),
                        if (previewHistory.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white10
                                    : const Color(0xFFECEAF2),
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.diamond_outlined,
                                  size: 40,
                                  color: scheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'No Lida Value activity yet',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white10
                                    : const Color(0xFFECEAF2),
                              ),
                              boxShadow: [
                                if (!isDark)
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                for (
                                  var i = 0;
                                  i < previewHistory.length;
                                  i++
                                ) ...[
                                  if (i > 0)
                                    Divider(
                                      height: 1,
                                      color: isDark
                                          ? Colors.white12
                                          : const Color(0xFFE5E3EC),
                                    ),
                                  _CompactHistoryRow(
                                    item: previewHistory[i],
                                    isCredit: _isCreditItem(previewHistory[i]),
                                    codeLabel: _codeLabel(previewHistory[i]),
                                    onTap: () => _showReceiptDetails(
                                      context,
                                      previewHistory[i],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Center(
                            child: TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => _LidaValueHistoryScreen(
                                      items: wallet.history,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.history_rounded,
                                color: AppColors.primary,
                                size: 20,
                              ),
                              label: const Text(
                                'View All History',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static void _showReceiptDetails(BuildContext context, ServiceReceipt item) {
    final isCredit = _isCreditItem(item);
    final friendlyTitle = _friendlyLabel(item);
    final codeLabel = _codeLabel(item);

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.86,
        child: _LidaValueDetailSheet(
          item: item,
          isCredit: isCredit,
          friendlyTitle: friendlyTitle,
          codeLabel: codeLabel,
        ),
      ),
    );
  }

  /// USE and SEND both buy airtime or data charged to the Lida Value wallet —
  /// the only difference is who receives it, so the choice here is just which
  /// wizard to enter. The wizards then handle self/SEND rules, registered
  /// recipients and recipient choice exactly like the momo flow.
  void _openTopupChooser(BuildContext context, {required bool forSelf}) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      // Without this the sheet is capped at ~half the screen, which clips the
      // chooser on short devices.
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _LidaValueTopupChooser(
        forSelf: forSelf,
        onPick: (isData) {
          Navigator.of(sheetContext).pop();
          final funding = forSelf ? 'lv-use' : 'lv-send';
          context.push(
            isData
                ? '/services/data?funding=$funding'
                : '/services/airtime?funding=$funding',
          );
        },
      ),
    );
  }

  Future<void> _openActionSheet(
    BuildContext context,
    WidgetRef ref, {
    required String action,
  }) async {
    final amount = TextEditingController();
    final destination = TextEditingController();
    final isConvert = action == 'convert';
    final title = switch (action) {
      'sell' => 'Sell Lida Value',
      _ => 'Convert Lida Value',
    };
    final subtitle = switch (action) {
      'sell' => 'Sell your Lida Value back to your main wallet.',
      _ => 'Convert Lida Value into mobile money, bank or crypto.',
    };

    var error = '';
    var busy = false;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              24 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(sheetContext).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount (LV)',
                    prefixIcon: Icon(Icons.diamond_outlined),
                  ),
                ),
                if (action == 'sell') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: destination,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Payout account (optional)',
                      hintText: 'MoMo number or bank account',
                      helperText:
                          'Leave empty to settle to your Lidapay wallet.',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    ),
                  ),
                ],
                if (isConvert) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: destination,
                    decoration: const InputDecoration(
                      labelText: 'Destination',
                      hintText: 'momo:0241234567',
                      helperText: 'Type:address — momo, bank, btc, eth or usdt',
                      prefixIcon: Icon(Icons.account_balance_rounded),
                    ),
                  ),
                ],
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                AppButton(
                  label: title,
                  loading: busy,
                  onPressed: () async {
                    if (busy) return;
                    final parsed = double.tryParse(amount.text.trim()) ?? 0;
                    if (parsed <= 0) {
                      setSheetState(() => error = 'Enter a valid LV amount.');
                      return;
                    }
                    setSheetState(() {
                      busy = true;
                      error = '';
                    });
                    final repo = ref.read(servicesRepositoryProvider);
                    try {
                      final isEligible = await repo.checkLidaValueEligibility();
                      if (!isEligible) {
                        setSheetState(() {
                          busy = false;
                          error =
                              'Your account is not currently eligible for '
                              '$title. Please contact support.';
                        });
                        return;
                      }
                      final receipt = switch (action) {
                        'sell' => await repo.sellLidaValue(
                          amount: parsed,
                          destination: destination.text.trim().isEmpty
                              ? null
                              : destination.text.trim(),
                        ),
                        _ => await repo.convertLidaValue(
                          amount: parsed,
                          destination: destination.text.trim(),
                        ),
                      };
                      if (!sheetContext.mounted) return;
                      Navigator.of(sheetContext).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${receipt.title} · ${receipt.reference}',
                          ),
                        ),
                      );
                      ref.invalidate(lidaValueProvider);
                    } on ApiException catch (failure) {
                      if (!sheetContext.mounted) return;
                      setSheetState(() {
                        busy = false;
                        error = failure.message;
                      });
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
    amount.dispose();
    destination.dispose();
  }
}

/// Small chooser shown under the USE/SEND pills — both actions buy airtime
/// or data charged to Lida Value, so the user only picks the service type.
class _LidaValueTopupChooser extends StatelessWidget {
  const _LidaValueTopupChooser({required this.forSelf, required this.onPick});

  final bool forSelf;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Material(
        color: isDark ? AppColors.darkScaffold : const Color(0xFFF6F6F9),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    forSelf ? 'Use Lida Value' : 'Send with Lida Value',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    forSelf
                        ? 'Buy airtime or data for your own number — charged '
                              'straight from your Lida Value.'
                        : 'Send airtime or data to another number — charged '
                              'from your Lida Value. Registered recipients can '
                              'still choose to save it instead.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _ChooserCard(
                    icon: Icons.call_rounded,
                    tint: AppColors.primary,
                    title: 'Airtime',
                    subtitle: 'Talk-time credit for any network.',
                    onTap: () => onPick(false),
                  ),
                  const SizedBox(height: 12),
                  _ChooserCard(
                    icon: Icons.wifi_tethering_rounded,
                    tint: AppColors.violet,
                    title: 'Data bundle',
                    subtitle: 'Internet bundles at operator rates.',
                    onTap: () => onPick(true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChooserCard extends StatelessWidget {
  const _ChooserCard({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? AppColors.darkSurface : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tint.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
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
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: tint),
            ],
          ),
        ),
      ),
    );
  }
}

class _LidaValueActionPill extends StatelessWidget {
  const _LidaValueActionPill({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark
          ? AppColors.primary.withValues(alpha: 0.14)
          : const Color(0xFFFCF0F5),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.45),
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactHistoryRow extends StatelessWidget {
  const _CompactHistoryRow({
    required this.item,
    required this.isCredit,
    required this.codeLabel,
    required this.onTap,
  });

  final ServiceReceipt item;
  final bool isCredit;
  final String codeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isCredit ? const Color(0xFF2FA84F) : const Color(0xFFE5484D);
    final bg = isCredit ? const Color(0xFFEAF8EE) : const Color(0xFFFDECEC);
    final sign = isCredit ? '+' : '-';
    final dateStr = DateFormat('d MMM, HH:mm').format(item.createdAt.toLocal());

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(
                isCredit
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$sign${item.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    codeLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              dateStr,
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LidaValueHistoryScreen extends StatefulWidget {
  const _LidaValueHistoryScreen({required this.items});

  final List<ServiceReceipt> items;

  @override
  State<_LidaValueHistoryScreen> createState() =>
      _LidaValueHistoryScreenState();
}

class _LidaValueHistoryScreenState extends State<_LidaValueHistoryScreen> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final cardBg = isDark ? AppColors.darkSurface : Colors.white;
    final filtered = widget.items.where((item) {
      final isCredit = LidaValueScreen._isCreditItem(item);
      if (_filter == 'Credit') return isCredit;
      if (_filter == 'Debit') return !isCredit;
      return true;
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? Colors.white10
                            : const Color(0xFFECEAF2),
                      ),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: scheme.onSurface,
                        size: 22,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Lida Value History',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    initialValue: _filter,
                    onSelected: (v) => setState(() => _filter = v),
                    icon: Icon(
                      Icons.filter_list_rounded,
                      color: scheme.onSurface,
                    ),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'All', child: Text('All Activity')),
                      PopupMenuItem(
                        value: 'Credit',
                        child: Text('Credits Only'),
                      ),
                      PopupMenuItem(value: 'Debit', child: Text('Debits Only')),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  final isCredit = LidaValueScreen._isCreditItem(item);
                  final friendly = LidaValueScreen._friendlyLabel(item);
                  final color = isCredit
                      ? const Color(0xFF2FA84F)
                      : const Color(0xFFE5484D);
                  final bg = isCredit
                      ? const Color(0xFFEAF8EE)
                      : const Color(0xFFFDECEC);
                  final sign = isCredit ? '+' : '-';
                  final dateStr = DateFormat('d MMM yyyy, HH:mm')
                      .format(item.createdAt.toLocal());

                  return GestureDetector(
                    onTap: () =>
                        LidaValueScreen._showReceiptDetails(context, item),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isDark
                              ? Colors.white10
                              : const Color(0xFFECEAF2),
                        ),
                        boxShadow: [
                          if (!isDark)
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: bg,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  isCredit
                                      ? Icons.arrow_downward_rounded
                                      : Icons.arrow_upward_rounded,
                                  color: color,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  friendly,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '$sign${item.amount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'VALUE',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurfaceVariant,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 15,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                dateStr,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  isCredit ? 'CREDIT' : 'DEBIT',
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LidaValueDetailSheet extends StatelessWidget {
  const _LidaValueDetailSheet({
    required this.item,
    required this.isCredit,
    required this.friendlyTitle,
    required this.codeLabel,
  });

  final ServiceReceipt item;
  final bool isCredit;
  final String friendlyTitle;
  final String codeLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final surfaceBg = isDark ? AppColors.darkScaffold : const Color(0xFFF6F6F9);
    final cardBg = isDark ? AppColors.darkSurface : Colors.white;
    final localDate = item.createdAt.toLocal();
    final dateStr = DateFormat('MMM d, yyyy').format(localDate);
    final timeStr = DateFormat('hh:mm a').format(localDate);
    final color = isCredit ? const Color(0xFF2FA84F) : const Color(0xFFE5484D);
    final bg = isCredit ? const Color(0xFFEAF8EE) : const Color(0xFFFDECEC);
    final sign = isCredit ? '+' : '-';

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Material(
        color: surfaceBg,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
              decoration: const BoxDecoration(gradient: AppColors.heroGradient),
              child: Column(
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 21,
                          ),
                        ),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Lida Value Details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Share.share(
                            'Lidapay Lida Value · $friendlyTitle · $sign${item.amount.toStringAsFixed(2)} LV · Ref: ${item.reference}',
                          );
                        },
                        icon: const Icon(
                          Icons.share_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.receipt_long_outlined,
                          size: 15,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.reference,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
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
                        border: Border.all(
                          color: isDark
                              ? Colors.white10
                              : const Color(0xFFECEAF2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: bg,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  isCredit
                                      ? Icons.arrow_downward_rounded
                                      : Icons.arrow_upward_rounded,
                                  color: color,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      friendlyTitle,
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      codeLabel,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  isCredit ? 'CREDIT' : 'DEBIT',
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Divider(height: 1),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Value Units',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '$sign${item.amount.toStringAsFixed(2)} LV',
                                style: TextStyle(
                                  color: color,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Date',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                dateStr,
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Time',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                timeStr,
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          if (item.message.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Details',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    item.message,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: scheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
                        border: Border.all(
                          color: isDark
                              ? Colors.white10
                              : const Color(0xFFECEAF2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF8EE),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF2FA84F),
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Status',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'COMPLETED',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF2FA84F),
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
