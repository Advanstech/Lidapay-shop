import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../dashboard/providers.dart';
import '../../services/data/service_models.dart';
import '../data/recipient_models.dart';
import '../providers.dart';

/// Sender-side "waiting for the recipient" surface shown right after the
/// credit call parks a top-up behind a recipient decision. Polls
/// `GET /topups/{id}/status` until the backend reports the final
/// disposition, so the sender sees the real outcome — never a fake
/// "delivered" receipt.
///
/// The countdown ring is the page's centre of gravity: the remaining time is
/// the only thing the sender can act on, and the arc around it shows it
/// running out, so the wait reads as a live process instead of a static
/// spinner with a timer bolted on.
class PendingTopupScreen extends ConsumerStatefulWidget {
  const PendingTopupScreen({
    super.key,
    required this.pending,
    required this.amountLabel,
    required this.recipientLabel,
    required this.serviceLabel,
    required this.icon,
    required this.onDone,
    this.onNewTransaction,
    this.newTransactionLabel = 'Continue transaction',
  });

  final PendingTopup pending;

  /// Human-readable amount ("GHS 10.00") and phone ("233…") shown while
  /// waiting — the status payload may not echo them back.
  final String amountLabel;
  final String recipientLabel;
  final String serviceLabel;
  final IconData icon;
  final VoidCallback onDone;

  /// Optional action allowing the sender to start another transaction right
  /// away while this parked top-up continues polling in the background.
  final VoidCallback? onNewTransaction;
  final String newTransactionLabel;

  @override
  ConsumerState<PendingTopupScreen> createState() => _PendingTopupScreenState();
}

class _PendingTopupScreenState extends ConsumerState<PendingTopupScreen> {
  Timer? _ticker;

  /// The window length as observed when this screen mounted. The API only
  /// publishes `expiresAt`, so the arc is drawn against the span actually
  /// watched here rather than a guessed total.
  Duration _window = Duration.zero;

  /// Countdown band driving page-level chrome (accent, settling copy).
  /// The page only rebuilds when the band flips — the live clock itself
  /// ticks inside [_CountdownHero] and [_SettleNote], which rebuild only
  /// their own small subtrees.
  int _band = 0;

  static const _bandWarn = Duration(seconds: 60);
  static const _bandClose = Duration(seconds: 20);

  late final StateController<String?> _activeWaitingCtrl;

  @override
  void initState() {
    super.initState();
    _activeWaitingCtrl = ref.read(activeWaitingTopupOrderIdProvider.notifier);
    _syncWindow();
    // No window means no countdown band to track; the status provider still
    // drives rebuilds when the transfer settles.
    if (_hasWindow) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
    Future<void>.microtask(() {
      if (!mounted) return;
      _activeWaitingCtrl.state = widget.pending.topupOrderId;
      registerTrackedPendingTopup(
        ref,
        topupOrderId: widget.pending.topupOrderId,
        recipient: widget.recipientLabel,
        serviceLabel: widget.serviceLabel,
      );
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    final id = widget.pending.topupOrderId;
    Future<void>.microtask(() {
      if (_activeWaitingCtrl.mounted && _activeWaitingCtrl.state == id) {
        _activeWaitingCtrl.state = null;
      }
    });
    super.dispose();
  }

  void _syncWindow() {
    final remaining = _remainingNow;
    _window = remaining;
    _band = _bandFor(remaining, hasWindow: _hasWindow);
  }

  Duration get _remainingNow {
    final exp = widget.pending.expiresAt;
    if (exp == null) return Duration.zero;
    final r = exp.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  bool get _hasWindow => widget.pending.expiresAt != null;

  /// 0 = plenty of time, 1 = under a minute, 2 = under 20s, 3 = window
  /// closed. Band 2 and 3 share the error accent; 3 additionally flips the
  /// page into its "settling" copy.
  static int _bandFor(Duration remaining, {required bool hasWindow}) {
    if (!hasWindow || remaining > _bandWarn) return 0;
    if (remaining > _bandClose) return 1;
    return remaining == Duration.zero ? 3 : 2;
  }

  void _tick() {
    if (!mounted) return;
    // Terminal status swaps in the result view — the countdown is moot, so
    // stop ticking entirely instead of burning a timer for the rest of
    // the session.
    final status = ref
        .read(topupStatusTrackerProvider(widget.pending.topupOrderId))
        .valueOrNull;
    if (status?.isTerminal == true) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    final band = _bandFor(_remainingNow, hasWindow: _hasWindow);
    if (band != _band) setState(() => _band = band);
  }

  bool get _settling => _band == 3;

  Future<void> _copyReference() async {
    await Clipboard.setData(ClipboardData(text: widget.pending.topupOrderId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('Reference copied'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracker = ref.watch(
      topupStatusTrackerProvider(widget.pending.topupOrderId),
    );
    final status = tracker.valueOrNull;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = status?.isTerminal == true
        ? status!.isDeliveredDirect
              ? AppColors.success
              : status.isDeliveredToLidaValue
              ? AppColors.violet
              : AppColors.error
        : _band == 0
        ? AppColors.primary
        : _band == 1
        ? AppColors.warning
        : AppColors.error;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.darkScaffold
          : AppColors.lightScaffold,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: _AmbientGlow(color: accent, isDark: isDark),
            ),
          ),
          SafeArea(
            child: status?.isTerminal == true
                ? _TerminalView(
                    status: status!,
                    recipientLabel: widget.recipientLabel,
                    onDone: widget.onDone,
                    onCopyReference: _copyReference,
                  )
                : _waitingBody(context, accent),
          ),
        ],
      ),
    );
  }

  Widget _waitingBody(BuildContext context, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFECEAF2);
    final muted = scheme.onSurfaceVariant;
    final settling = _settling;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
      children: [
        _Header(
          title: 'Sending top-up',
          subtitle: widget.amountLabel,
          onBack: widget.onDone,
        ),
        const SizedBox(height: 10),
        _CountdownHero(
          expiresAt: widget.pending.expiresAt,
          window: _window,
          accent: accent,
          track: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : AppColors.navy.withValues(alpha: 0.08),
          surface: surface,
        ),
        const SizedBox(height: 20),
        Text(
          settling
              ? 'Completing transfer'
              : 'Waiting for ${widget.recipientLabel}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            settling
                ? 'Your value is being credited to ${widget.recipientLabel}\'s '
                      'Lida Value wallet and is ready for them to use.'
                : '${widget.recipientLabel} is on Lidapay and can choose '
                      'between this ${widget.serviceLabel} now or keeping '
                      'the value in their Lida Value wallet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 13.5, height: 1.45),
          ),
        ),
        const SizedBox(height: 22),
        _RecipientCard(
          recipientLabel: widget.recipientLabel,
          icon: widget.icon,
          accent: accent,
          surface: surface,
          border: border,
          muted: muted,
          settling: settling,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text(
              'THEIR OPTIONS',
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
                color: muted.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Divider(color: border, thickness: 1)),
          ],
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ChoiceCard(
                  icon: widget.icon,
                  tint: AppColors.success,
                  title: 'Take it now',
                  detail: 'Straight to ${widget.recipientLabel}',
                  surface: surface,
                  border: border,
                  muted: muted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ChoiceCard(
                  icon: Icons.diamond_rounded,
                  tint: AppColors.violet,
                  title: 'Keep the value',
                  detail: 'Saved to their Lida Value wallet',
                  surface: surface,
                  border: border,
                  muted: muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SummaryCard(
          amountLabel: widget.amountLabel,
          reference: widget.pending.topupOrderId,
          surface: surface,
          border: border,
          muted: muted,
          onCopyReference: _copyReference,
        ),
        const SizedBox(height: 14),
        _SettleNote(accent: accent, expiresAt: widget.pending.expiresAt),
        const SizedBox(height: 22),
        if (widget.onNewTransaction != null) ...[
          AppButton(
            label: widget.newTransactionLabel,
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: Colors.white,
              size: 19,
            ),
            onPressed: widget.onNewTransaction,
          ),
          const SizedBox(height: 10),
        ],
        _LeaveButton(
          label: widget.onNewTransaction != null
              ? 'Go to Home'
              : 'Continue in background',
          onPressed: widget.onDone,
          accent: accent,
          surface: surface,
        ),
        const SizedBox(height: 10),
        Text(
          'Runs in the background — we\'ll notify you once '
          '${widget.recipientLabel} responds or it credits to their Lida Value wallet.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 11.5, height: 1.4),
        ),
      ],
    );
  }
}

/// Soft radial wash behind the page so the surface never reads as flat black.
class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({required this.color, required this.isDark});

  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.92),
          radius: 1.15,
          colors: [
            color.withValues(alpha: isDark ? 0.24 : 0.13),
            color.withValues(alpha: isDark ? 0.06 : 0.03),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        _GlassIconButton(icon: Icons.arrow_back_rounded, onTap: onBack),
        Expanded(
          child: Column(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        // Symmetry for the back button so the title stays optically centred.
        const SizedBox(width: 40),
      ],
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : const Color(0xFFECEAF2),
          ),
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }
}

/// The hero: pulse rings reaching outward, a depleting arc, and the clock.
/// Owns its own 1s ticker so the countdown only rebuilds this subtree —
/// the page around it rebuilds solely on countdown-band changes.
class _CountdownHero extends StatefulWidget {
  const _CountdownHero({
    required this.expiresAt,
    required this.window,
    required this.accent,
    required this.track,
    required this.surface,
  });

  final DateTime? expiresAt;

  /// Window length observed at screen mount — the arc depletes against it.
  final Duration window;
  final Color accent;
  final Color track;
  final Color surface;

  @override
  State<_CountdownHero> createState() => _CountdownHeroState();
}

class _CountdownHeroState extends State<_CountdownHero> {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  late Duration _window = widget.window;

  @override
  void initState() {
    super.initState();
    _tick();
    if (widget.window <= Duration.zero) _window = _remaining;
    _startIfNeeded();
  }

  /// No window (or an already-closed one) renders a static label — run the
  /// 1s clock only while there is actually something counting down.
  void _startIfNeeded() {
    final exp = widget.expiresAt;
    if (exp == null || !exp.isAfter(DateTime.now())) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    final exp = widget.expiresAt;
    if (!mounted || exp == null) return;
    final r = exp.difference(DateTime.now());
    if (r.isNegative) {
      _timer?.cancel();
      _timer = null;
    }
    setState(() {
      _remaining = r.isNegative ? Duration.zero : r;
    });
  }

  bool get _hasWindow => widget.expiresAt != null;

  bool get _settled => _hasWindow && _remaining == Duration.zero;

  bool get _showCountdown => _hasWindow && !_settled;

  /// 1.0 = the whole window is still left, 0.0 = it just closed.
  double get _fraction {
    if (_window <= Duration.zero) return 0;
    return (_remaining.inMilliseconds / _window.inMilliseconds).clamp(0.0, 1.0);
  }

  String get _clock {
    final mm = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accent;
    final track = widget.track;
    final surface = widget.surface;
    final showCountdown = _showCountdown;
    final settled = _settled;
    final hasWindow = _hasWindow;
    return SizedBox(
      height: 224,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _PulseRings(color: accent, size: 224),
          if (showCountdown)
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: _fraction),
              duration: const Duration(milliseconds: 950),
              curve: Curves.linear,
              builder: (context, value, _) => CustomPaint(
                size: const Size.square(188),
                painter: _CountdownRingPainter(
                  progress: value,
                  accent: accent,
                  track: track,
                ),
              ),
            )
          else
            SizedBox(
              width: 188,
              height: 188,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                strokeCap: StrokeCap.round,
                color: accent,
                backgroundColor: track,
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showCountdown)
                Text(
                  _clock,
                  style: TextStyle(
                    fontSize: 46,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2,
                    color: scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                )
              else
                Icon(
                  settled
                      ? Icons.hourglass_bottom_rounded
                      : Icons.hourglass_top_rounded,
                  size: 34,
                  color: accent,
                ),
              const SizedBox(height: 6),
              Text(
                showCountdown
                    ? 'LEFT TO DECIDE'
                    : settled
                    ? 'SETTLING'
                    : hasWindow
                    ? 'WAITING'
                    : 'CHECKING STATUS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          // Service badge pinned to the ring, so the hero still names the
          // product once the clock owns the centre.
          if (showCountdown)
            Positioned(
              bottom: 0,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: track, width: 1.5),
                  boxShadow: AppShadows.glow(accent, alpha: 0.35, blur: 18),
                ),
                child: Icon(Icons.bolt_rounded, size: 21, color: accent),
              ),
            ),
        ],
      ),
    );
  }
}

/// Three rings breathing outward — "we're knocking on their door".
class _PulseRings extends StatefulWidget {
  const _PulseRings({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<_PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<_PulseRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _PulseRingsPainter(
              progress: _controller.value,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseRingsPainter extends CustomPainter {
  _PulseRingsPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final inner = outer * 0.60;
    final paint = Paint()..style = PaintingStyle.stroke;
    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      final radius = inner + (outer - inner) * t;
      paint
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: (1 - t) * 0.30);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_PulseRingsPainter old) =>
      old.progress != progress || old.color != color;
}

class _CountdownRingPainter extends CustomPainter {
  _CountdownRingPainter({
    required this.progress,
    required this.accent,
    required this.track,
  });

  /// Share of the window still left, 0..1.
  final double progress;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const stroke = 7.0;
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (progress <= 0) return;

    final sweep = 2 * math.pi * progress;

    // Halo first, so the crisp arc sits on top of its own glow.
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.40)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [accent, Color.lerp(accent, Colors.white, 0.35)!, accent],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_CountdownRingPainter old) =>
      old.progress != progress || old.accent != accent || old.track != track;
}

class _RecipientCard extends StatelessWidget {
  const _RecipientCard({
    required this.recipientLabel,
    required this.icon,
    required this.accent,
    required this.surface,
    required this.border,
    required this.muted,
    required this.settling,
  });

  final String recipientLabel;
  final IconData icon;
  final Color accent;
  final Color surface;
  final Color border;
  final Color muted;
  final bool settling;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(15),
              boxShadow: AppShadows.glow(AppColors.primary, alpha: 0.28),
            ),
            child: Icon(icon, color: Colors.white, size: 23),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipientLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      settling ? 'Decision window closed' : 'Lidapay member',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    if (!settling) ...[
                      const SizedBox(width: 6),
                      _WaitingDots(color: accent),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Three dots ticking — a quiet "still waiting on them" signal.
class _WaitingDots extends StatefulWidget {
  const _WaitingDots({required this.color});

  final Color color;

  @override
  State<_WaitingDots> createState() => _WaitingDotsState();
}

class _WaitingDotsState extends State<_WaitingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(right: i == 2 ? 0 : 3),
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: widget.color.withValues(
                    alpha: _opacity(i, _controller.value),
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Staggered fade: each dot peaks a third of a cycle after the previous.
  double _opacity(int index, double t) {
    final phase = (t + index / 3) % 1.0;
    final triangle = 1 - (phase - 0.5).abs() * 2;
    return 0.25 + 0.75 * triangle.clamp(0.0, 1.0);
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.tint,
    required this.title,
    required this.detail,
    required this.surface,
    required this.border,
    required this.muted,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String detail;
  final Color surface;
  final Color border;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 17, color: tint),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            detail,
            style: TextStyle(fontSize: 11.5, color: muted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.amountLabel,
    required this.reference,
    required this.surface,
    required this.border,
    required this.muted,
    required this.onCopyReference,
  });

  final String amountLabel;
  final String reference;
  final Color surface;
  final Color border;
  final Color muted;
  final VoidCallback onCopyReference;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Amount', style: TextStyle(fontSize: 12.5, color: muted)),
              Text(
                amountLabel,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Divider(height: 1, thickness: 1, color: border),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Reference', style: TextStyle(fontSize: 12.5, color: muted)),
              Flexible(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onCopyReference,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          reference,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.copy_rounded, size: 14, color: muted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Self-ticking so the "no answer by HH:MM:SS" line updates without
/// rebuilding the rest of the page.
class _SettleNote extends StatefulWidget {
  const _SettleNote({required this.accent, required this.expiresAt});

  final Color accent;
  final DateTime? expiresAt;

  @override
  State<_SettleNote> createState() => _SettleNoteState();
}

class _SettleNoteState extends State<_SettleNote> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _startIfNeeded();
  }

  /// The "closed" copy is static — tick only while the window is open.
  void _startIfNeeded() {
    final exp = widget.expiresAt;
    if (exp == null || !exp.isAfter(DateTime.now())) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    final exp = widget.expiresAt;
    if (!mounted || exp == null) return;
    final r = exp.difference(DateTime.now());
    if (r.isNegative) {
      _timer?.cancel();
      _timer = null;
    }
    setState(() {
      _remaining = r.isNegative ? Duration.zero : r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final hasWindow = widget.expiresAt != null;
    final closed = hasWindow && _remaining == Duration.zero;
    final mm = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    final clock = '$mm:$ss';
    final text = !hasWindow
        ? 'Checking the recipient\'s delivery preference.'
        : closed
        ? 'Completing transfer — crediting their Lida Value wallet.'
        : 'If they haven\'t picked by $clock, the value credits to their '
              'Lida Value wallet automatically.';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppRadii.chip),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            closed ? Icons.sync_rounded : Icons.auto_awesome_rounded,
            size: 16,
            color: accent,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaveButton extends StatelessWidget {
  const _LeaveButton({
    required this.label,
    required this.onPressed,
    required this.accent,
    required this.surface,
  });

  final String label;
  final VoidCallback onPressed;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(AppRadii.button),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadii.button),
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.button),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, size: 17, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalView extends StatelessWidget {
  const _TerminalView({
    required this.status,
    required this.recipientLabel,
    required this.onDone,
    required this.onCopyReference,
  });

  final TopupOrderStatus status;
  final String recipientLabel;
  final VoidCallback onDone;
  final VoidCallback onCopyReference;

  @override
  Widget build(BuildContext context) {
    final recipient =
        status.recipientPhone ??
        status.decision?.recipientPhone ??
        recipientLabel;
    final (icon, color, title, body) = status.isDeliveredDirect
        ? (
            Icons.check_circle_rounded,
            AppColors.success,
            'Delivered to $recipient',
            'Your ${status.serviceLabel} top-up has been credited directly to '
                '$recipient.',
          )
        : status.isDeliveredToLidaValue
        ? (
            Icons.diamond_rounded,
            AppColors.violet,
            'Credited to $recipient\'s Lida Value',
            status.decision?.resolvedSource == 'TIMEOUT'
                ? 'The value was automatically credited to $recipient\'s '
                      'Lida Value wallet and is ready for them to use anytime.'
                : '$recipient chose to receive the value in their Lida Value '
                      'wallet.',
          )
        : (
            Icons.error_outline_rounded,
            AppColors.error,
            'Could not be delivered',
            '${Formatters.friendlyFailureReason(status.failedReason)}\n\n'
            'If you were charged, contact support with reference '
            '${status.topupOrderId}.',
          );

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                boxShadow: AppShadows.glow(color, alpha: 0.30, blur: 30),
              ),
              child: Icon(icon, size: 54, color: color),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCopyReference,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ref ${status.topupOrderId}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.copy_rounded,
                      size: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            AppButton(label: 'Done', onPressed: onDone),
          ],
        ),
      ),
    );
  }
}
