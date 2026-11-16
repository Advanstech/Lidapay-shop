import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/deep_links.dart';
import 'core/network/connectivity_service.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers.dart';
import 'features/recipient_choice/providers.dart';

/// App-wide scroll behavior that gives both Android and iOS a smooth,
/// elastic, native feel (and allows mouse/trackpad drag in Chrome DevTools).
class LidapayScrollBehavior extends MaterialScrollBehavior {
  const LidapayScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(
      decelerationRate: ScrollDecelerationRate.normal,
      parent: AlwaysScrollableScrollPhysics(),
    );
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // BouncingScrollPhysics handles overscroll elastically; no glow overlay.
    return child;
  }
}

class LidapayApp extends ConsumerStatefulWidget {
  const LidapayApp({super.key});

  @override
  ConsumerState<LidapayApp> createState() => _LidapayAppState();
}

class _LidapayAppState extends ConsumerState<LidapayApp>
    with WidgetsBindingObserver {
  PaymentDeepLinkHandler? _deepLinks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyEdgeToEdge();
    final router = ref.read(routerProvider);

    // Initialize Push & Local Notifications with the GoRouter instance
    ref.read(pushNotificationServiceProvider).initialize(router: router);

    // AppLinks streams `lidapay://` payment returns for the lifetime of the
    // app; URIs that arrive before a session exists are parked until
    // [hasSessionProvider] flips, then flushed once.
    _deepLinks = PaymentDeepLinkHandler(
      router: router,
      hasSession: () => ref.read(hasSessionProvider),
    );
    _deepLinks!.start();
    ref.listenManual(hasSessionProvider, (_, _) => _deepLinks?.flush());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deepLinks?.dispose();
    super.dispose();
  }

  /// Returning from the ExpressPay browser, biometrics, or a permission
  /// dialog can re-inset the window on Samsung/Huawei devices — keep the
  /// app edge-to-edge like other modern apps. Also refresh the profile so
  /// verification flags (e.g. an email link opened in the browser) and
  /// other server-side state are current when the user comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyEdgeToEdge();
      unawaited(ref.read(authSessionProvider.notifier).refreshProfile());
      if (ref.read(hasSessionProvider)) {
        unawaited(ref.read(pushNotificationServiceProvider).syncDeviceToken());
        unawaited(ref.read(pendingRecipientDecisionsProvider.notifier).refresh());
      }
    }
  }

  void _applyEdgeToEdge() {
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {
      // Platform channel not attached yet (early init) — harmless.
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;

    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    // Dynamic System Navigation Bar & Status Bar overlay styling
    // Designed for Samsung One UI, Google Pixel, and standard Android navigation
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: MaterialApp.router(
        title: 'Lidapay',
        debugShowCheckedModeBanner: false,
        scrollBehavior: const LidapayScrollBehavior(),
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        routerConfig: router,
        builder: (context, child) {
          // Automatic keyboard dismissal on outside tap (smooth redrawal)
          final content = GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: child ?? const SizedBox.shrink(),
          );

          if (isOnline) return content;

          // Non-blocking offline awareness banner
          return Column(
            children: [
              Expanded(child: content),
              Material(
                color: Colors.red.shade800,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.wifi_off_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'No internet connection. Waiting for network…',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
