import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/sticky_header.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/providers.dart';
import '../../services/data/service_models.dart';
import '../../services/providers.dart';

/// Destination types available for Lida Value conversion.
/// Crypto (btc/eth/usdt) is intentionally excluded — not yet ready on the backend.
enum _ConvertDestination { momo, bank }

/// Dedicated Convert page for Lida Value.
///
/// Converts LV into mobile money or a bank account. The destination follows
/// the spec format `type:address`, e.g. `momo:0241234567` or `bank:1234567890`.
class ConvertScreen extends StatefulWidget {
  const ConvertScreen({super.key});

  @override
  State<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends State<ConvertScreen> {
  final _amount = TextEditingController();
  final _destination = TextEditingController();
  _ConvertDestination _destinationType = _ConvertDestination.momo;
  String? _error;
  bool _busy = false;
  ServiceReceipt? _receipt;

  String get _formattedDestination {
    final raw = _destination.text.trim().replaceAll(RegExp(r'\D'), '');
    if (_destinationType == _ConvertDestination.momo) {
      var digits = raw;
      if (digits.startsWith('233') && digits.length == 12) {
        digits = '0${digits.substring(3)}';
      } else if (digits.length == 9 && !digits.startsWith('0')) {
        digits = '0$digits';
      }
      return 'momo:$digits';
    }
    return 'bank:$raw';
  }

  double get _amountValue => double.tryParse(_amount.text.trim()) ?? 0;

  bool get _canConvert =>
      _amountValue > 0 && _destination.text.trim().isNotEmpty && !_busy;

  @override
  void dispose() {
    _amount.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _convert(WidgetRef ref) async {
    if (!_canConvert) return;
    setState(() {
      _busy = true;
      _error = null;
      _receipt = null;
    });
    try {
      final isEligible = await ref
          .read(servicesRepositoryProvider)
          .checkLidaValueEligibility();
      if (!isEligible) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'Your account is not currently eligible for conversion. Please contact support.';
        });
        return;
      }
      final receipt = await ref
          .read(servicesRepositoryProvider)
          .convertLidaValue(
            amount: _amountValue,
            destination: _formattedDestination,
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _receipt = receipt;
      });
      ref.invalidate(lidaValueProvider);
    } on ApiException catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final scheme = Theme.of(context).colorScheme;
        final cardBg = isDark ? AppColors.darkSurface : Colors.white;
        final user = ref.watch(authSessionProvider)?.user;

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: StickySliverHeaderDelegate(
                  height: MediaQuery.paddingOf(context).top + 68,
                  builder: (context, isStuck) => DecoratedBox(
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkScaffold
                          : AppColors.lightScaffold,
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
                      padding: EdgeInsets.fromLTRB(
                        20,
                        MediaQuery.paddingOf(context).top + 10,
                        20,
                        10,
                      ),
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
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: AppColors.primary,
                                size: 22,
                              ),
                              tooltip: 'Back',
                              onPressed: () => context.pop(),
                            ),
                          ),
                          const Expanded(
                            child: Center(
                              child: Text(
                                'Convert Lida Value',
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
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
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
                            const Text(
                              'Convert Lida Value',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  (user?.phoneNumber ?? '—'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 34,
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
                            const SizedBox(height: 16),
                            Text(
                              'Convert LV into mobile money or a bank account.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13.5,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Amount
                      Text(
                        'Amount (LV)',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: InputDecoration(
                          hintText: '0.00',
                          suffixText: ' LV',
                          filled: true,
                          fillColor: isDark
                              ? AppColors.darkInput
                              : const Color(0xFFF5F4FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Destination type
                      Text(
                        'Destination type',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _DestinationTypeCard(
                              type: _ConvertDestination.momo,
                              selected:
                                  _destinationType == _ConvertDestination.momo,
                              label: 'Mobile Money',
                              subtitle: 'Send to a MoMo number',
                              icon: Icons.phone_android_rounded,
                              onTap: () => setState(
                                () =>
                                    _destinationType = _ConvertDestination.momo,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DestinationTypeCard(
                              type: _ConvertDestination.bank,
                              selected:
                                  _destinationType == _ConvertDestination.bank,
                              label: 'Bank Account',
                              subtitle: 'Send to a bank account',
                              icon: Icons.account_balance_wallet_rounded,
                              onTap: () => setState(
                                () =>
                                    _destinationType = _ConvertDestination.bank,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Destination input
                      Text(
                        'Destination number / account',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _destination,
                        keyboardType: TextInputType.phone,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: _destinationType == _ConvertDestination.momo
                              ? '0241234567'
                              : '1234567890',
                          prefixText:
                              _destinationType == _ConvertDestination.momo
                              ? 'momo:'
                              : 'bank:',
                          filled: true,
                          fillColor: isDark
                              ? AppColors.darkInput
                              : const Color(0xFFF5F4FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: scheme.error,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      if (_receipt != null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.success.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.success,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Conversion complete',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_receipt!.title} · ${_receipt!.reference}',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      AppButton(
                        label: _busy
                            ? 'Converting…'
                            : _receipt != null
                            ? 'Convert again'
                            : 'Convert',
                        loading: _busy,
                        onPressed: _canConvert || _receipt != null
                            ? () => _convert(ref)
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Done'),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DestinationTypeCard extends StatelessWidget {
  const _DestinationTypeCard({
    required this.type,
    required this.selected,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final _ConvertDestination type;
  final bool selected;
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.1)
                : _cardBg(isDark),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : (isDark ? Colors.white10 : const Color(0xFFECEAF2)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary
                      : (isDark
                            ? AppColors.darkInput
                            : const Color(0xFFF5F4FA)),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: selected ? Colors.white : AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: selected ? AppColors.primary : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _cardBg(bool isDark) =>
      isDark ? AppColors.darkSurface : const Color(0xFFF5F4FA);
}
