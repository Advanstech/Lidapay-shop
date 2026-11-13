import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import 'country_flag_badge.dart';

/// Review ticket shared by the Airtime and Data wizards.
///
/// Collapsed it shows the essentials — carrier, amount, recipient — without
/// repeating anything. Tapping "Order details" expands the full, editable
/// order list (big rows, one tap to jump back to that wizard step), so a
/// customer can verify and fix everything without leaving the screen.
class TopupReviewCard extends StatefulWidget {
  const TopupReviewCard({
    super.key,
    required this.serviceLabel,
    required this.heroValue,
    this.heroCaption,
    required this.networkName,
    required this.countryName,
    required this.countryFlag,
    this.countryFlagUrl,
    this.operatorLogoUrl,
    required this.recipientPhone,
    this.isSelf = false,
    required this.deliveryNote,
    this.payWith,
    this.payAmount,
    this.amountRowLabel = 'Amount',
    this.amountRowValue,
    this.onChangeCountry,
    this.onChangeRecipient,
    this.onChangeNetwork,
    this.onChangeAmount,
  });

  final String serviceLabel;
  final String heroValue;
  final String? heroCaption;
  final String networkName;
  final String countryName;
  final String countryFlag;
  final String? countryFlagUrl;
  final String? operatorLogoUrl;
  final String recipientPhone;

  /// True when the recipient is the signed-in user's own number.
  final bool isSelf;

  /// One sentence on what happens after paying.
  final String deliveryNote;

  /// `Mobile Money`, … Null hides the line (e.g. Lida Value funding already
  /// has its own balance card below the ticket).
  final String? payWith;

  /// Shown beside [payWith] only when it differs from the hero (FX charge,
  /// Lida Value cost, bundle price). Null hides it.
  final String? payAmount;

  final String amountRowLabel;
  final String? amountRowValue;

  final VoidCallback? onChangeCountry;
  final VoidCallback? onChangeRecipient;
  final VoidCallback? onChangeNetwork;
  final VoidCallback? onChangeAmount;

  @override
  State<TopupReviewCard> createState() => _TopupReviewCardState();
}

class _TopupReviewCardState extends State<TopupReviewCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final divider = Divider(
      height: 1,
      color: isDark ? Colors.white10 : const Color(0xFFF0EEF5),
    );

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hero: carrier identity + the amount ────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            decoration: const BoxDecoration(gradient: AppColors.heroGradient),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: widget.onChangeNetwork,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: OperatorLogoBadge(
                          name: widget.networkName,
                          logoUrl: widget.operatorLogoUrl,
                          size: 38,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.networkName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  '${widget.serviceLabel} · ',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                CountryFlagBadge(
                                  isoCode: widget.countryFlag,
                                  flagUrl: widget.countryFlagUrl,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    widget.countryName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
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
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: widget.onChangeAmount,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                widget.heroValue,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.8,
                                  height: 1.05,
                                ),
                              ),
                            ),
                            if (widget.heroCaption != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                widget.heroCaption!,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.78),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.onChangeAmount != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Icon(
                            Icons.edit_rounded,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Recipient row ──────────────────────────────────────────────
          InkWell(
            onTap: widget.onChangeRecipient,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 17, 14, 17),
              child: Row(
                children: [
                  Icon(
                    widget.isSelf
                        ? Icons.person_rounded
                        : Icons.send_rounded,
                    size: 21,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.recipientPhone,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        if (widget.isSelf) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'You',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy number',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: widget.recipientPhone),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Number copied'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    icon: Icon(Icons.copy_rounded, size: 18, color: muted),
                  ),
                ],
              ),
            ),
          ),

          // ── Expandable order details ───────────────────────────────────
          divider,
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long_rounded,
                    size: 19,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Order details',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                children: [
                  _DetailRow(
                    icon: Icons.public_rounded,
                    iconColor: const Color(0xFF2E9BD6),
                    leading: CountryFlagBadge(
                      isoCode: widget.countryFlag,
                      flagUrl: widget.countryFlagUrl,
                      size: 28,
                    ),
                    label: 'Country',
                    value: widget.countryName,
                    onEdit: widget.onChangeCountry,
                  ),
                  divider,
                  _DetailRow(
                    icon: Icons.cell_tower_rounded,
                    iconColor: const Color(0xFF7B4FE0),
                    leading: OperatorLogoBadge(
                      name: widget.networkName,
                      logoUrl: widget.operatorLogoUrl,
                      size: 30,
                    ),
                    label: 'Network',
                    value: widget.networkName,
                    onEdit: widget.onChangeNetwork,
                  ),
                  divider,
                  _DetailRow(
                    icon: Icons.payments_outlined,
                    iconColor: const Color(0xFF33B457),
                    label: widget.amountRowLabel,
                    value: widget.amountRowValue ?? widget.heroValue,
                    onEdit: widget.onChangeAmount,
                  ),
                  divider,
                  _DetailRow(
                    icon: Icons.phone_iphone_rounded,
                    iconColor: const Color(0xFFE2608F),
                    label: 'Phone number',
                    value: widget.recipientPhone,
                    onEdit: widget.onChangeRecipient,
                  ),
                  divider,
                  _DetailRow(
                    icon: Icons.bolt_rounded,
                    iconColor: const Color(0xFF33B457),
                    label: 'Delivery',
                    value: widget.deliveryNote,
                    valueIsSentence: true,
                  ),
                  if (widget.payWith != null) ...[
                    divider,
                    _DetailRow(
                      icon: Icons.account_balance_wallet_outlined,
                      iconColor: const Color(0xFF8A8299),
                      label: 'Payment',
                      value: widget.payWith!,
                      trailing: widget.payAmount,
                    ),
                  ],
                ],
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }
}

/// One big, legible row of the expanded order list — icon, label stacked
/// over the value, and an Edit affordance that jumps back to that step.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.iconColor,
    this.leading,
    required this.label,
    required this.value,
    this.onEdit,
    this.trailing,
    this.valueIsSentence = false,
  });

  final IconData icon;
  final Color iconColor;
  final Widget? leading;
  final String label;
  final String value;
  final VoidCallback? onEdit;
  final String? trailing;
  final bool valueIsSentence;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            alignment: Alignment.center,
            child: leading ?? Icon(icon, size: 21, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: valueIsSentence ? 14.5 : 16,
                    fontWeight: valueIsSentence
                        ? FontWeight.w600
                        : FontWeight.w800,
                    height: 1.3,
                    color: scheme.onSurface,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    trailing!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onEdit != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onEdit,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Edit',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
