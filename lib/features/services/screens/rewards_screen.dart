import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/skeleton.dart';
import '../../auth/providers.dart';
import '../data/service_models.dart';
import '../providers.dart';

/// Lida Points hub — hero balance card, redeem catalogue driven by
/// GET /lidapoints/redeem/options, and the earn/redeem activity ledger.
class LidaPointsScreen extends ConsumerWidget {
  const LidaPointsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(lidaPointsProvider);
    final options = ref.watch(pointsRedeemOptionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkScaffold : null,
      body: points.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: AppSkeletonScreen(),
        ),
        error: (error, _) => ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(lidaPointsProvider),
        ),
        data: (wallet) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(lidaPointsProvider);
            ref.invalidate(pointsRedeemOptionsProvider);
            await ref.read(lidaPointsProvider.future);
          },
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: _PointsHero(wallet: wallet, isDark: isDark),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                  child: Text(
                    'Redeem points',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: options.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: AppSkeleton(height: 120, borderRadius: 20),
                  ),
                  error: (_, _) => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox.shrink(),
                  ),
                  data: (opts) => opts.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            children: [
                              for (final option in opts) ...[
                                _RedeemOptionTile(
                                  option: option,
                                  wallet: wallet,
                                  isDark: isDark,
                                ),
                                const SizedBox(height: 10),
                              ],
                            ],
                          ),
                        ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Row(
                    children: [
                      Text(
                        'Points activity',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Text(
                        '${wallet.history.length} entries',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (wallet.history.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyView(
                    title: 'No points activity yet',
                    subtitle:
                        'Earn points on every airtime, data and shop purchase.',
                    icon: Icons.workspace_premium_outlined,
                  ),
                )
              else
                SliverList.separated(
                  itemCount: wallet.history.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => _PointsActivityRow(
                    receipt: wallet.history[index],
                    isDark: isDark,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PointsHero extends StatelessWidget {
  const _PointsHero({required this.wallet, required this.isDark});

  final LidaPointsWallet wallet;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        22,
        MediaQuery.paddingOf(context).top + 14,
        22,
        24,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B2040), Color(0xFF4C2E8F)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                color: Colors.white,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Lida Points',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Available points',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Formatters.compact(wallet.balance),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'PTS',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '≈ ${Formatters.currency(wallet.redeemableValue)} cash value',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RedeemOptionTile extends ConsumerWidget {
  const _RedeemOptionTile({
    required this.option,
    required this.wallet,
    required this.isDark,
  });

  final PointsRedeemOption option;
  final LidaPointsWallet wallet;
  final bool isDark;

  IconData get _icon => switch (option.id.toLowerCase()) {
    'airtime' || 'call' => Icons.call_rounded,
    'data' || 'internet' => Icons.wifi_rounded,
    'cash_momo' || 'momo' || 'cash' => Icons.payments_rounded,
    'lida_value' || 'value' => Icons.diamond_rounded,
    _ => Icons.redeem_rounded,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final affordable =
        option.minPoints == 0 || wallet.balance >= option.minPoints;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: affordable ? 1 : 0.55,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _openRedeemSheet(context, ref),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(_icon, color: AppColors.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          option.minPoints > 0
                              ? '${Formatters.compact(option.minPoints)} pts minimum'
                                  '${option.description.isNotEmpty ? ' · ${option.description}' : ''}'
                              : option.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openRedeemSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RedeemSheet(option: option, balance: wallet.balance),
    );
  }
}

/// Option → amount → quote → confirm, matching the old app's
/// options/quote/confirm contract with a client idempotency key.
class _RedeemSheet extends ConsumerStatefulWidget {
  const _RedeemSheet({required this.option, required this.balance});

  final PointsRedeemOption option;
  final int balance;

  @override
  ConsumerState<_RedeemSheet> createState() => _RedeemSheetState();
}

class _RedeemSheetState extends ConsumerState<_RedeemSheet> {
  final _points = TextEditingController();
  final _destination = TextEditingController();
  late final String _idempotencyKey =
      'LPR-${DateTime.now().microsecondsSinceEpoch}';
  PointsRedeemQuote? _quote;
  bool _quoting = false;
  bool _confirming = false;
  String? _error;

  int get _pointsValue => int.tryParse(_points.text) ?? 0;

  bool get _canQuote =>
      _pointsValue > 0 &&
      _pointsValue <= widget.balance &&
      _pointsValue >= widget.option.minPoints &&
      (!_requiresDestination || _destination.text.trim().isNotEmpty);

  bool get _requiresDestination {
    final registered = normalizePhone();
    return widget.option.needsDestination && registered.isEmpty;
  }

  String normalizePhone() {
    var digits = _destination.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('233') && digits.length == 12) {
      digits = '0${digits.substring(3)}';
    }
    return digits;
  }

  @override
  void initState() {
    super.initState();
    final registered =
        ref.read(authSessionProvider)?.user.phoneNumber ?? '';
    _destination.text = registered.replaceAll(RegExp(r'[^0-9]'), '');
    if (_destination.text.startsWith('233')) {
      _destination.text = '0${_destination.text.substring(3)}';
    }
  }

  @override
  void dispose() {
    _points.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _getQuote() async {
    if (!_canQuote || _quoting) return;
    setState(() {
      _quoting = true;
      _error = null;
    });
    try {
      final quote = await ref
          .read(servicesRepositoryProvider)
          .getPointsRedeemQuote(
            points: _pointsValue.toDouble(),
            optionId: widget.option.id,
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

  Future<void> _confirm() async {
    final quote = _quote;
    if (quote == null || _confirming) return;
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
      if (mounted) Navigator.of(context).pop(receipt);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkScaffold : const Color(0xFFF7F6FB),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
          22,
          18,
          22,
          MediaQuery.paddingOf(context).bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Redeem · ${widget.option.name}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'Balance: ${Formatters.compact(widget.balance)} pts',
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _points,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) {
                if (_quote != null) setState(() => _quote = null);
              },
              decoration: InputDecoration(
                labelText: 'Points to redeem',
                helperText: widget.option.minPoints > 0
                    ? 'Minimum ${Formatters.compact(widget.option.minPoints)} pts'
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
            if (widget.option.needsDestination) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _destination,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(12),
                ],
                decoration: InputDecoration(
                  labelText: 'Destination number / account',
                  helperText: 'Where the redeemed value should land',
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
            const SizedBox(height: 14),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  style: TextStyle(color: scheme.error, fontSize: 12.5),
                ),
              ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _quote == null
                  ? AppButton(
                      key: const ValueKey('quote'),
                      label: _quoting ? 'Getting quote…' : 'Get quote',
                      loading: _quoting,
                      onPressed: _canQuote && !_quoting ? _getQuote : null,
                    )
                  : Column(
                      key: const ValueKey('confirm'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                          onPressed: _confirming ? null : _confirm,
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

class _PointsActivityRow extends StatelessWidget {
  const _PointsActivityRow({required this.receipt, required this.isDark});

  final dynamic receipt;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCredit = receipt.isCredit ?? true;
    final label = receipt.isCredit == null
        ? ''
        : (isCredit ? '+' : '-');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: (isCredit ? AppColors.success : AppColors.primary).withValues(
            alpha: 0.1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          isCredit ? Icons.add_circle_rounded : Icons.redeem_rounded,
          size: 20,
          color: isCredit ? AppColors.success : AppColors.primary,
        ),
      ),
      title: Text(
        receipt.title.toString().replaceAll('_', ' '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        receipt.message.toString().isEmpty
            ? 'Settled'
            : receipt.message.toString(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      trailing: Text(
        '$label${Formatters.compact((receipt.amount as num).round())} PTS',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: isCredit ? AppColors.success : scheme.onSurface,
        ),
      ),
    );
  }
}

/// Invite & Earn — referral code, invite stats and share actions.
class InviteEarnScreen extends ConsumerWidget {
  const InviteEarnScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final affiliate = ref.watch(affiliateSummaryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkScaffold : null,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.fromLTRB(
                22,
                MediaQuery.paddingOf(context).top + 14,
                22,
                24,
              ),
              decoration: const BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(30),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Invite & Earn',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Share your code — earn points when friends join and transact.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          affiliate.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: AppSkeletonScreen(),
              ),
            ),
            error: (e, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorView(
                message: e.toString(),
                onRetry: () => ref.invalidate(affiliateSummaryProvider),
              ),
            ),
            data: (data) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Referral code card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurface : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark
                              ? Colors.white10
                              : const Color(0xFFECEAF2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'YOUR INVITE CODE',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SelectableText(
                            data.code.isEmpty ? '—' : data.code,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.copy_rounded, size: 18),
                                  label: const Text('Copy'),
                                  onPressed: data.code.isEmpty
                                      ? null
                                      : () {
                                          Clipboard.setData(
                                            ClipboardData(text: data.code),
                                          );
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Invite code copied',
                                              ),
                                            ),
                                          );
                                        },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: AppButton(
                                  label: 'Share',
                                  icon: const Icon(
                                    Icons.share_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  onPressed: data.code.isEmpty
                                      ? null
                                      : () {
                                          Share.share(
                                            'Join me on LidaPay — instant '
                                            'airtime, data and shopping. '
                                            'Use my invite code ${data.code} '
                                            'when you sign up.',
                                          );
                                        },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Stats row
                    Row(
                      children: [
                        _InviteStat(
                          icon: Icons.group_outlined,
                          value: '${data.totalInvites}',
                          label: 'Invites',
                          isDark: isDark,
                        ),
                        const SizedBox(width: 10),
                        _InviteStat(
                          icon: Icons.how_to_reg_outlined,
                          value: '${data.activeUsers}',
                          label: 'Active',
                          isDark: isDark,
                        ),
                        const SizedBox(width: 10),
                        _InviteStat(
                          icon: Icons.payments_outlined,
                          value: Formatters.currency(data.earnings),
                          label: 'Earned',
                          isDark: isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.workspace_premium_outlined,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Friends earn a bonus on signup, and you earn '
                              'Lida Points on their first transactions.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteStat extends StatelessWidget {
  const _InviteStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.isDark,
  });

  final IconData icon;
  final String value;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
