import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../data/service_models.dart';

/// Full-screen success receipt after a delivered purchase — celebratory
/// header with the amount front and centre, then a clean detail card and a
/// copyable reference. Shared by airtime, data and wallet-funded flows.
class ServiceReceiptScreen extends StatelessWidget {
  const ServiceReceiptScreen({
    super.key,
    required this.receipt,
    required this.icon,
    required this.onDone,
  });

  final ServiceReceipt receipt;
  final IconData icon;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Hero: gradient band, success badge, title, message.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                    decoration: const BoxDecoration(
                      gradient: AppColors.heroGradient,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(30),
                      ),
                    ),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: GestureDetector(
                            onTap: onDone,
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 21,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.6, end: 1),
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.elasticOut,
                          builder: (context, scale, child) =>
                              Transform.scale(scale: scale, child: child),
                          child: Container(
                            width: 92,
                            height: 92,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Container(
                                width: 68,
                                height: 68,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  size: 40,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          receipt.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          receipt.message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Amount + reference card.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurface : Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isDark
                              ? Colors.white10
                              : const Color(0xFFECEAF2),
                        ),
                        boxShadow: [
                          if (!isDark)
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            Formatters.currency(receipt.amount),
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Charged',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Divider(
                              height: 1,
                              color: isDark
                                  ? Colors.white10
                                  : const Color(0xFFF0EEF5),
                            ),
                          ),
                          _ReceiptRow(
                            label: 'Status',
                            valueWidget: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF33B457,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Delivered',
                                style: TextStyle(
                                  color: Color(0xFF33B457),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _ReceiptRow(
                            label: 'Date',
                            value: Formatters.dateTime(
                              receipt.createdAt.toLocal(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _ReceiptRow(
                            label: 'Reference',
                            value: receipt.reference,
                            mono: true,
                            trailing: IconButton(
                              tooltip: 'Copy reference',
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: receipt.reference),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Reference copied'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                              icon: Icon(
                                Icons.copy_rounded,
                                size: 17,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom CTA.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Done',
                      icon: const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: onDone,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => _ReceiptShareSheet.show(context, receipt),
                      child: const SizedBox(
                        width: 56,
                        height: 56,
                        child: Icon(
                          Icons.ios_share_rounded,
                          color: AppColors.primary,
                          size: 21,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.trailing,
    this.mono = false,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;
  final Widget? trailing;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: valueWidget ??
              Text(
                value ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: mono ? 12.5 : 14,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                  fontFamily: mono ? 'monospace' : null,
                ),
              ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Bottom sheet with the exportable receipt rendered visibly (required for
/// `RepaintBoundary.toImage`) plus the share action. The share sheet on
/// Android/iOS covers save-to-files and every installed share target; when
/// file sharing isn't available (e.g. desktop web) it falls back to a
/// formatted text receipt.
class _ReceiptShareSheet extends StatefulWidget {
  const _ReceiptShareSheet({required this.receipt});

  final ServiceReceipt receipt;

  static Future<void> show(BuildContext context, ServiceReceipt receipt) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReceiptShareSheet(receipt: receipt),
    );
  }

  @override
  State<_ReceiptShareSheet> createState() => _ReceiptShareSheetState();
}

class _ReceiptShareSheetState extends State<_ReceiptShareSheet> {
  final _boundaryKey = GlobalKey();
  bool _busy = false;

  String get _textReceipt =>
      'LidaPay receipt\n${widget.receipt.title}\n'
      '${widget.receipt.message}\n'
      'Amount: ${Formatters.currency(widget.receipt.amount)}\n'
      'Reference: ${widget.receipt.reference}\n'
      'Date: ${Formatters.dateTime(widget.receipt.createdAt.toLocal())}';

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return;
      await Share.shareXFiles(
        [
          XFile.fromData(
            png.buffer.asUint8List(),
            name: 'lidapay-receipt-${widget.receipt.reference}.png',
            mimeType: 'image/png',
          ),
        ],
        subject: 'LidaPay receipt ${widget.receipt.reference}',
      );
    } catch (_) {
      // File sharing unavailable (e.g. desktop web) — the text summary is
      // still a complete, verifiable receipt.
      await Share.share(_textReceipt);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Share receipt',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Send it to anyone or save it to your files.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  RepaintBoundary(
                    key: _boundaryKey,
                    child: _ReceiptDocument(receipt: widget.receipt),
                  ),
                  const SizedBox(height: 20),
                  AppButton(
                    label: 'Share / Save',
                    loading: _busy,
                    icon: const Icon(
                      Icons.ios_share_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    onPressed: _share,
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

/// The image that gets shared — always light and branded regardless of the
/// app's theme, so the PNG reads like a real till receipt everywhere.
class _ReceiptDocument extends StatelessWidget {
  const _ReceiptDocument({required this.receipt});

  final ServiceReceipt receipt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFECEAF2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Brand band.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
            decoration: const BoxDecoration(gradient: AppColors.heroGradient),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LIDAPAY',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Payment receipt',
                  style: TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  Formatters.currency(receipt.amount),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: Color(0xFF1D1B24),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF33B457).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'SUCCESSFUL',
                    style: TextStyle(
                      color: Color(0xFF33B457),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const _DashedDivider(),
                const SizedBox(height: 14),
                _DocRow(label: 'Service', value: receipt.title),
                const SizedBox(height: 10),
                _DocRow(label: 'Details', value: receipt.message),
                const SizedBox(height: 10),
                _DocRow(
                  label: 'Date',
                  value: Formatters.dateTime(receipt.createdAt.toLocal()),
                ),
                const SizedBox(height: 10),
                _DocRow(
                  label: 'Reference',
                  value: receipt.reference,
                  mono: true,
                ),
                const SizedBox(height: 14),
                const _DashedDivider(),
                const SizedBox(height: 12),
                Text(
                  'Thank you for using LidaPay.\nGenerated '
                  '${Formatters.dateTime(DateTime.now())}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.5,
                    color: Color(0xFF8B8798),
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

class _DocRow extends StatelessWidget {
  const _DocRow({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8B8798),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: mono ? 11.5 : 12.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1D1B24),
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final count = (constraints.maxWidth / 10).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: 5,
                height: 1.2,
                color: const Color(0xFFD9D6E4),
              ),
          ],
        );
      },
    );
  }
}
