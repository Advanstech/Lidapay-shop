import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/sticky_header.dart';
import '../../auth/providers.dart';
import '../data/service_models.dart';
import '../providers.dart';

/// Dedicated Lida Points redeem page.
///
/// Option → amount → quote → confirm, matching the old app's
/// options/quote/confirm contract with a client idempotency key.
///
/// The [optionId] is looked up from the available redeem options so the
/// page can be reached directly via `/services/lida-points/redeem?optionId=…`.
class RedeemScreen extends StatefulWidget {
  const RedeemScreen({super.key, required this.optionId});

  final String optionId;

  @override
  State<RedeemScreen> createState() => _RedeemScreenState();
}

class _RedeemScreenState extends State<RedeemScreen> {
  final _points = TextEditingController();
  final _destination = TextEditingController();
  late final String _idempotencyKey =
      'LPR-${DateTime.now().microsecondsSinceEpoch}';
  PointsRedeemOption? _option;
  PointsRedeemQuote? _quote;
  bool _loadingOptions = true;
  bool _quoting = false;
  bool _confirming = false;
  String? _error;
  ServiceReceipt? _receipt;

  int get _pointsValue => int.tryParse(_points.text) ?? 0;

  bool _canQuote(WidgetRef ref) =>
      _option != null &&
      _pointsValue > 0 &&
      _pointsValue <= _balance(ref) &&
      _pointsValue >= _option!.minPoints &&
      (!_requiresDestination(ref) || _destination.text.trim().isNotEmpty);

  bool _requiresDestination(WidgetRef ref) {
    if (_option == null) return false;
    final registered = normalizePhone();
    return _option!.needsDestination && registered.isEmpty;
  }

  int _balance(WidgetRef ref) {
    final wallet = ref.read(lidaPointsProvider).valueOrNull;
    return wallet?.balance ?? 0;
  }

  String normalizePhone() {
    var digits = _destination.text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('233') && digits.length == 12) {
      digits = '0${digits.substring(3)}';
    }
    return digits;
  }

  @override
  void dispose() {
    _points.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _loadOptions(WidgetRef ref) async {
    try {
      final opts = await ref
          .read(servicesRepositoryProvider)
          .getPointsRedeemOptions();
      if (!mounted) return;
      setState(() {
        _option = opts.firstWhere(
          (o) => o.id == widget.optionId,
          orElse: () => opts.first,
        );
        _loadingOptions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingOptions = false);
    }
  }

  Future<void> _getQuote(WidgetRef ref) async {
    if (!_canQuote(ref) || _quoting || _option == null) return;
    setState(() {
      _quoting = true;
      _error = null;
    });
    try {
      final quote = await ref
          .read(servicesRepositoryProvider)
          .getPointsRedeemQuote(
            points: _pointsValue.toDouble(),
            optionId: _option!.id,
          );
      if (mounted) setState(() => _quote = quote);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not quote this redemption. Try again.');
      }
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _confirm(WidgetRef ref) async {
    final quote = _quote;
    final option = _option;
    if (quote == null || option == null || _confirming) return;
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final receipt = await ref
          .read(servicesRepositoryProvider)
          .confirmPointsRedeem(
            quoteId: quote.quoteId,
            destination: _destination.text.trim().isEmpty
                ? null
                : _destination.text.trim(),
            idempotencyKey: _idempotencyKey,
          );
      ref.invalidate(lidaPointsProvider);
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _receipt = receipt;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Redemption failed. Your points were not deducted.',
        );
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        // Load options and prefill phone on first build
        if (_loadingOptions && _option == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loadOptions(ref);
          });
        }
        // Prefill destination with the signed-in phone number (local format)
        if (_destination.text.isEmpty) {
          final registered =
              ref.read(authSessionProvider)?.user.phoneNumber ?? '';
          if (registered.isNotEmpty) {
            var digits = registered.replaceAll(RegExp(r'\D'), '');
            if (digits.startsWith('233') && digits.length == 12) {
              digits = '0${digits.substring(3)}';
            }
            _destination.text = digits;
          }
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final scheme = Theme.of(context).colorScheme;
        final cardBg = isDark ? AppColors.darkSurface : Colors.white;
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        final option = _option;

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
                              onPressed: () => context.pop(_receipt),
                            ),
                          ),
                          const Expanded(
                            child: Center(
                              child: Text(
                                'Redeem Points',
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
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + bottomInset),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_loadingOptions)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            ),
                          ),
                        )
                      else ...[
                        Text(
                          'Redeem · ${option?.name ?? '…'}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Balance: ${Formatters.compact(_balance(ref))} pts',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Points input
                        Text(
                          'Points to redeem',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _points,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) {
                            if (_quote != null) setState(() => _quote = null);
                            setState(() {});
                          },
                          decoration: InputDecoration(
                            hintText: '0',
                            helperText: (option?.minPoints ?? 0) > 0
                                ? 'Minimum ${Formatters.compact(option!.minPoints)} pts'
                                : null,
                            filled: true,
                            fillColor: isDark
                                ? AppColors.darkInput
                                : const Color(0xFFF6F5FA),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        if (option?.needsDestination ?? false) ...[
                          const SizedBox(height: 20),
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
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(12),
                            ],
                            decoration: InputDecoration(
                              hintText: '0241234567',
                              filled: true,
                              fillColor: isDark
                                  ? AppColors.darkInput
                                  : const Color(0xFFF6F5FA),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: scheme.error,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        // Quote / confirm section
                        if (_quote == null)
                          AppButton(
                            label: _quoting ? 'Getting quote…' : 'Get quote',
                            loading: _quoting,
                            onPressed: _canQuote(ref) && !_quoting
                                ? () => _getQuote(ref)
                                : null,
                          )
                        else ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.success.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.price_check_rounded,
                                  color: AppColors.success,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${Formatters.compact(_quote!.points.round())} pts '
                                    '→ ${Formatters.currency(_quote!.cashValue)} '
                                    '${_quote!.currency}'
                                    '${_quote!.message.isNotEmpty ? '\n${_quote!.message}' : ''}',
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AppButton(
                            label: _confirming
                                ? 'Redeeming…'
                                : 'Confirm redemption',
                            icon: const Icon(
                              Icons.redeem_rounded,
                              color: Colors.white,
                            ),
                            loading: _confirming,
                            onPressed: _confirming ? null : () => _confirm(ref),
                          ),
                        ],
                        const SizedBox(height: 20),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Redemption complete',
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
                          AppButton(
                            label: 'Done',
                            onPressed: () => context.pop(_receipt),
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
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
