import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/brand_mark.dart';

class _Page {
  const _Page({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.art,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final String art;
}

/// Art-led onboarding. Forces a dark cinematic look in both app themes —
/// the artwork is overlaid with a black scrim so text stays legible.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _pages = [
    _Page(
      eyebrow: 'AIRTIME & DATA',
      title: 'Stay connected, wherever life happens',
      subtitle: 'Top up your own phone or someone else’s in Ghana and around the world, with clear review before you pay.',
      art: 'assets/images/onboarding_globe.png',
    ),
    _Page(
      eyebrow: 'LIDA VALUE',
      title: 'Value that stays ready for you',
      subtitle: 'Use Lida Value for airtime and data, send it to someone else, or explore eligible buyback options.',
      art: 'assets/images/onboarding_wallet.png',
    ),
    _Page(
      eyebrow: 'SHOP & REWARDS',
      title: 'Partner deals and rewards in one place',
      subtitle: 'Discover products and vouchers from trusted partners, track your orders, and grow your Lida Points.',
      art: 'assets/images/onboarding_growth.png',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await markOnboardingSeen();
    if (mounted) context.go(AppRoutes.login);
  }

  void _next() {
    if (_index == _pages.length - 1) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _controller,
        itemCount: _pages.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final page = _pages[i];
          final isLastPage = i == _pages.length - 1;

          return Stack(
            fit: StackFit.expand,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  double offset = 0;
                  if (_controller.hasClients &&
                      _controller.position.haveDimensions) {
                    offset =
                        (_controller.page ??
                            _controller.initialPage.toDouble()) -
                        i;
                  }
                  // Counteract the page swipe slightly to create a parallax effect
                  return Transform.translate(
                    offset: Offset(offset * 150, 0),
                    child: child,
                  );
                },
                child: Image.asset(
                  page.art,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black26,
                      Colors.transparent,
                      Color(0xCC000000),
                      Color(0xF5000000),
                    ],
                    stops: [0, 0.35, 0.68, 1],
                  ),
                ),
              ),
              SafeArea(
                child: CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: 24,
                          right: 24,
                          top: 32,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const BrandMark(
                                  size: 34,
                                  radius: 11,
                                  fontSize: 18,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Lidapay',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const Spacer(),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _finish,
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.2,
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        'Skip',
                                        style: TextStyle(
                                          fontFamily: 'Plus Jakarta Sans',
                                          color: Colors.white.withValues(
                                            alpha: 0.9,
                                          ),
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            const SizedBox(height: 32),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  page.eyebrow,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  page.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 30,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  page.subtitle,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.72,
                                        ),
                                        height: 1.5,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),
                            Row(
                              children: [
                                for (
                                  var dotIndex = 0;
                                  dotIndex < _pages.length;
                                  dotIndex++
                                )
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    margin: const EdgeInsets.only(right: 6),
                                    width: dotIndex == _index ? 30 : 10,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: dotIndex == _index
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            AppButton(
                              label: isLastPage ? 'Get started' : 'Continue',
                              icon: isLastPage
                                  ? null
                                  : const Icon(
                                      Icons.arrow_forward_rounded,
                                      color: Colors.white,
                                    ),
                              onPressed: _next,
                            ),
                            if (isLastPage) ...[
                              const SizedBox(height: 14),
                              Center(
                                child: TextButton(
                                  onPressed: _finish,
                                  child: Text(
                                    'Already have an account? Sign in',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ] else
                              const SizedBox(height: 48),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
