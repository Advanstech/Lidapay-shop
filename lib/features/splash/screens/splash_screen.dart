import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../auth/providers.dart';

/// Branded cold-start splash: logo reveal over a navy gradient with glow
/// orbs, then routes to home / login / onboarding.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // Kept alive for the full display window so the navigator hand-off
      // happens while frames are still being scheduled.
      duration: const Duration(milliseconds: 2400),
    )..forward();
    _timer = Timer(const Duration(milliseconds: 2400), _route);
  }

  Future<void> _route() async {
    final seen = await hasSeenOnboarding();
    final notifier = ref.read(authSessionProvider.notifier);
    if (!notifier.didAttemptRestore) {
      await notifier.restore();
    }
    if (!mounted) return;
    final hasSession = ref.read(authSessionProvider) != null;
    if (hasSession) {
      context.go(AppRoutes.home);
    } else {
      context.go(seen ? AppRoutes.login : AppRoutes.onboarding);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markScale = Tween<double>(begin: 0.55, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.45, curve: Curves.easeOutBack),
      ),
    );
    final markOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.3)),
    );
    final wordOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.35, 0.6)),
    );
    final tagOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 0.75)),
    );
    final progress = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1, curve: Curves.easeInOut),
      ),
    );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0C0A1C), Color(0xFF1A1440)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -60,
              child: _GlowOrb(color: const Color(0xFFE31C5F), size: 260),
            ),
            Positioned(
              bottom: -100,
              left: -80,
              child: _GlowOrb(color: const Color(0xFF7B2FF7), size: 300),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) => Opacity(
                      opacity: markOpacity.value,
                      child: Transform.scale(
                        scale: markScale.value,
                        child: child,
                      ),
                    ),
                    child: const BrandMark(size: 92, useDark: true),
                  ),
                  const SizedBox(height: 28),
                  AnimatedBuilder(
                    animation: wordOpacity,
                    builder: (context, child) =>
                        Opacity(opacity: wordOpacity.value, child: child),
                    child: Text(
                      'Lidapay',
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AnimatedBuilder(
                    animation: tagOpacity,
                    builder: (context, child) =>
                        Opacity(opacity: tagOpacity.value, child: child),
                    child: Text(
                      'Money, moving beautifully.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 15,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 56),
                child: AnimatedBuilder(
                  animation: progress,
                  builder: (context, child) => Container(
                    width: 120 * progress.value,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: 0.25 + 0.55 * progress.value,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 140,
            spreadRadius: 20,
          ),
        ],
      ),
    );
  }
}
