import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../data/payment_models.dart';
import '../providers.dart';

/// What the user confirmed on the payment sheet.
class PaymentChoice {
  const PaymentChoice({
    required this.method,
    this.momoNumber,
    this.momoNetwork,
  });

  final PaymentMethod method;
  final String? momoNumber;
  final String? momoNetwork;
}

/// Opens the dedicated Lidapay payment sheet — shown *after* the user has
/// reviewed and confirmed their order. Returns null if dismissed.
///
/// [showMobileMoney] hides the GTPay `debitwallet` rail when false — the
/// shop contract keeps that option disabled until GTBank finishes
/// production onboarding (ExpressPay checkout already accepts MoMo).
Future<PaymentChoice?> showPaymentMethodSheet({
  required BuildContext context,
  required String amountLabel,
  required String orderSummary,
  required String registeredNumber,
  bool showMobileMoney = true,
}) {
  return showModalBottomSheet<PaymentChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _PaymentSheet(
      amountLabel: amountLabel,
      orderSummary: orderSummary,
      registeredNumber: registeredNumber,
      showMobileMoney: showMobileMoney,
    ),
  );
}

enum _MomoNet {
  mtn(
    'MTN MoMo',
    'MTN',
    Color(0xFFFFCB05),
    Color(0xFF1A1400),
    '024 · 054 · 055 · 059',
  ),
  telecel(
    'Telecel Cash',
    'TELECEL',
    Color(0xFFE60000),
    Colors.white,
    '020 · 050',
  ),
  at(
    'AirtelTigo',
    'AT',
    Color(0xFF0055A5),
    Colors.white,
    '026 · 027 · 056 · 057',
  );

  const _MomoNet(
    this.label,
    this.badge,
    this.brand,
    this.onBrand,
    this.prefixes,
  );
  final String label;
  final String badge;
  final Color brand;
  final Color onBrand;
  final String prefixes;

  static _MomoNet? fromNumber(String raw) {
    final digits = normalizeMomoNumber(raw);
    if (digits.length < 3) return null;
    return switch (digits.substring(0, 3)) {
      '024' || '025' || '053' || '054' || '055' || '059' => _MomoNet.mtn,
      '020' || '050' => _MomoNet.telecel,
      '026' || '027' || '056' || '057' => _MomoNet.at,
      _ => null,
    };
  }
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({
    required this.amountLabel,
    required this.orderSummary,
    required this.registeredNumber,
    required this.showMobileMoney,
  });

  final String amountLabel;
  final String orderSummary;
  final String registeredNumber;
  final bool showMobileMoney;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late PaymentMethod _method =
      widget.showMobileMoney ? PaymentMethod.mobileMoney : PaymentMethod.card;
  late _MomoNet _net;
  late bool _customWallet;
  late final String _registered;
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _registered = normalizeMomoNumber(widget.registeredNumber);
    final hasDefault = isValidMomoNumber(_registered);
    _customWallet = !hasDefault;
    _net = _MomoNet.fromNumber(_registered) ?? _MomoNet.mtn;
    if (hasDefault) _controller.text = _registered;
    _controller.addListener(_onTyped);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTyped);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTyped() {
    final detected = _MomoNet.fromNumber(_controller.text);
    setState(() {
      if (detected != null) _net = detected;
    });
  }

  void _pickDefaultWallet() {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() {
      _customWallet = false;
      _controller.text = _registered;
      _net = _MomoNet.fromNumber(_registered) ?? _net;
    });
  }

  void _pickCustomWallet([_MomoNet? network]) {
    HapticFeedback.selectionClick();
    setState(() {
      if (network != null) _net = network;
      if (!_customWallet) {
        _customWallet = true;
        if (network != null && _MomoNet.fromNumber(_registered) != network) {
          _controller.clear();
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  String get _activeNumber =>
      _customWallet ? normalizeMomoNumber(_controller.text) : _registered;

  bool get _ready =>
      _method == PaymentMethod.card || isValidMomoNumber(_activeNumber);

  void _confirm() {
    if (!_ready) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(
      PaymentChoice(
        method: _method,
        momoNumber: _method == PaymentMethod.mobileMoney ? _activeNumber : null,
        momoNetwork: _method == PaymentMethod.mobileMoney ? _net.label : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkScaffold : const Color(0xFFF7F6FB),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Header(
              amountLabel: widget.amountLabel,
              orderSummary: widget.orderSummary,
              onClose: () => Navigator.of(context).pop(),
            ),
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.showMobileMoney) ...[
                      _SegmentedRailPicker(
                        method: _method,
                        isDark: isDark,
                        onChanged: (m) {
                          HapticFeedback.selectionClick();
                          FocusScope.of(context).unfocus();
                          setState(() => _method = m);
                        },
                      ),
                      const SizedBox(height: 18),
                    ],
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: _method == PaymentMethod.mobileMoney
                          ? _buildMomoSection(isDark, scheme)
                          : _buildCardSection(isDark, scheme),
                    ),
                  ],
                ),
              ),
            ),
            _BottomPayBar(
              isDark: isDark,
              safeBottom: safeBottom,
              ready: _ready,
              label: _method == PaymentMethod.mobileMoney
                  ? 'Send Prompt · ${widget.amountLabel}'
                  : 'Continue to Card · ${widget.amountLabel}',
              subtitle: _method == PaymentMethod.mobileMoney && _ready
                  ? '${_net.label} · $_activeNumber'
                  : '256-bit encrypted · Lidapay Checkout',
              onConfirm: _confirm,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMomoSection(bool isDark, ColorScheme scheme) {
    final hasDefault = isValidMomoNumber(_registered);
    final defaultNet = _MomoNet.fromNumber(_registered) ?? _MomoNet.mtn;
    final typed = normalizeMomoNumber(_controller.text);
    final showError = _customWallet && typed.length >= 10 && !_ready;

    return Column(
      key: const ValueKey('momo'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasDefault) ...[
          _SectionLabel('Registered wallet', scheme),
          const SizedBox(height: 8),
          _DefaultWalletCard(
            number: _registered,
            net: defaultNet,
            selected: !_customWallet,
            isDark: isDark,
            onTap: _pickDefaultWallet,
            onSwitch: () => _pickCustomWallet(),
          ),
          const SizedBox(height: 18),
        ],
        Row(
          children: [
            Expanded(
              child: _SectionLabel(
                hasDefault
                    ? 'Or choose network & enter another wallet'
                    : 'Choose network & enter wallet number',
                scheme,
              ),
            ),
            if (hasDefault && _customWallet)
              TextButton(
                onPressed: _pickDefaultWallet,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Use default'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final net in _MomoNet.values) ...[
              Expanded(
                child: _NetworkCard(
                  net: net,
                  selected: _net == net,
                  isDark: isDark,
                  onTap: () {
                    if (hasDefault &&
                        !_customWallet &&
                        defaultNet == net) {
                      return;
                    }
                    _pickCustomWallet(net);
                  },
                ),
              ),
              if (net != _MomoNet.values.last) const SizedBox(width: 10),
            ],
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _customWallet
              ? Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: showError
                            ? AppColors.error
                            : AppColors.primary.withValues(alpha: 0.45),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _NetBadge(net: _net),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_net.label} wallet number',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _net.prefixes,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _controller,
                          focusNode: _focus,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                          decoration: InputDecoration(
                            hintText: '024 000 0000',
                            errorText: showError
                                ? 'Enter a valid 10-digit Ghana MoMo number'
                                : null,
                            prefixIcon: const Icon(
                              Icons.account_balance_wallet_outlined,
                            ),
                            suffixIcon: _controller.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: _controller.clear,
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                  ),
                            filled: true,
                            fillColor: isDark
                                ? AppColors.darkInput
                                : const Color(0xFFF5F4FA),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 14),
        _InfoBanner(
          icon: Icons.notifications_active_outlined,
          text: _ready
              ? 'We’ll send a ${widget.amountLabel} authorization prompt to '
                    '$_activeNumber (${_net.label}). Enter your MoMo PIN on '
                    'your phone to complete payment.'
              : 'Enter the 10-digit wallet number that will receive and '
                    'approve the payment prompt.',
        ),
      ],
    );
  }

  Widget _buildCardSection(bool isDark, ColorScheme scheme) {
    return Container(
      key: const ValueKey('card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const _CardBrandPill(
                label: 'VISA',
                bg: Color(0xFF1A1F71),
                fg: Colors.white,
              ),
              const _CardBrandPill(
                label: 'Mastercard',
                bg: Color(0xFFEB001B),
                fg: Colors.white,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.public_rounded,
                      size: 13,
                      color: AppColors.success,
                    ),
                    SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Local & International',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Pay with Debit or Credit Card',
            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Both Ghana and international Visa & Mastercard cards are '
            'accepted. You’ll complete 3-D Secure verification on the '
            'ExpressPay checkout and return straight to Lidapay.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          const _InfoBanner(
            icon: Icons.verified_user_outlined,
            text:
                'Card details are entered on ExpressPay and never stored on '
                'this device.',
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.amountLabel,
    required this.orderSummary,
    required this.onClose,
  });

  final String amountLabel;
  final String orderSummary;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 10, 14, 20),
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lidapay Checkout',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      orderSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'AMOUNT',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    amountLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentedRailPicker extends StatelessWidget {
  const _SegmentedRailPicker({
    required this.method,
    required this.isDark,
    required this.onChanged,
  });

  final PaymentMethod method;
  final bool isDark;
  final ValueChanged<PaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : const Color(0xFFECEAF4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentTab(
              icon: Icons.phone_android_rounded,
              label: 'Mobile Money',
              selected: method == PaymentMethod.mobileMoney,
              onTap: () => onChanged(PaymentMethod.mobileMoney),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _SegmentTab(
              icon: Icons.credit_card_rounded,
              label: 'Debit / Credit Card',
              selected: method == PaymentMethod.card,
              onTap: () => onChanged(PaymentMethod.card),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: selected ? AppColors.brandGradient : null,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          if (selected)
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? Colors.white : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : scheme.onSurfaceVariant,
                    ),
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

class _DefaultWalletCard extends StatelessWidget {
  const _DefaultWalletCard({
    required this.number,
    required this.net,
    required this.selected,
    required this.isDark,
    required this.onTap,
    required this.onSwitch,
  });

  final String number;
  final _MomoNet net;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? AppColors.primary
              : (isDark ? Colors.white10 : const Color(0xFFECEAF2)),
          width: selected ? 1.8 : 1,
        ),
        boxShadow: [
          if (selected && !isDark)
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                _NetBadge(net: net, size: 44),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            number,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: const Text(
                              'Default',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${net.label} · Registered number',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onSwitch,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text(
                    'Change',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? AppColors.primary : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard({
    required this.net,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final _MomoNet net;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: selected ? 1.0 : 0.97,
      duration: const Duration(milliseconds: 180),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? net.brand
                : (isDark ? Colors.white10 : const Color(0xFFECEAF2)),
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: net.brand.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(
                children: [
                  _NetBadge(net: net, size: 36),
                  const SizedBox(height: 7),
                  Text(
                    net.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
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

class _NetBadge extends StatelessWidget {
  const _NetBadge({required this.net, this.size = 28});

  final _MomoNet net;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: net.brand,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: Text(
        net.badge,
        style: TextStyle(
          color: net.onBrand,
          fontSize: size * 0.26,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

class _CardBrandPill extends StatelessWidget {
  const _CardBrandPill({
    required this.label,
    required this.bg,
    required this.fg,
  });

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, this.scheme);
  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      color: scheme.onSurfaceVariant,
    ),
  );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.38,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomPayBar extends StatelessWidget {
  const _BottomPayBar({
    required this.isDark,
    required this.safeBottom,
    required this.ready,
    required this.label,
    required this.subtitle,
    required this.onConfirm,
  });

  final bool isDark;
  final double safeBottom;
  final bool ready;
  final String label;
  final String subtitle;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, safeBottom + 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: ready ? AppColors.brandGradient : null,
              color: ready
                  ? null
                  : (isDark ? AppColors.darkInput : const Color(0xFFE5E5EA)),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                if (ready)
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.32),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(26),
                onTap: ready ? onConfirm : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_rounded,
                        size: 18,
                        color: ready ? Colors.white : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            color:
                                ready ? Colors.white : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11.5,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
