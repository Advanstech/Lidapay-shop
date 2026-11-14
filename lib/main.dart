import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/device/device_identity.dart';
import 'core/network/token_store.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers.dart';

void main() {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Configure Edge-to-Edge display on Android 10+ and Samsung One UI
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // Global Framework Error Handler (prevents crashes from layout bugs)
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('LidaPay Caught FlutterError: ${details.exceptionAsString()}');
    };

    // Platform Dispatched Root Error Handler
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      debugPrint('LidaPay Caught Platform Error: $error');
      return true; // Handled; avoid crashing host process
    };

    ProviderContainer? appContainer;

    // Graceful Error Widget Builder (anti-red screen of death in production)
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        color: AppColors.darkScaffold,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    color: AppColors.primary,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'LidaPay',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'An unexpected display issue occurred. Your data is safe.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      try {
                        appContainer?.read(routerProvider).go(AppRoutes.home);
                        WidgetsBinding.instance.reassembleApplication();
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh Screen'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    };

    final prefs = await SharedPreferences.getInstance();

    // Load device identity (stable UUID, platform, manufacturer, app version)
    final identity = await DeviceIdentityLoader.load(prefs);

    // Initialize Keystore/Keychain secure secret store and migrate any legacy prefs
    final tokenStore = TokenStore(prefs, secrets: SecureSecretStore());
    try {
      await tokenStore.load();
    } catch (e) {
      debugPrint('Token store load non-fatal warning: $e');
    }

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        tokenStoreProvider.overrideWithValue(tokenStore),
        deviceIdentityProvider.overrideWithValue(identity),
      ],
    );
    appContainer = container;

    // Fast-boot with bounded timeout: prevent splash freeze if network/keystore is slow
    try {
      await container
          .read(authSessionProvider.notifier)
          .restore()
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('Startup session restore timed out or failed: $e');
    }

    runApp(
      UncontrolledProviderScope(container: container, child: const LidapayApp()),
    );
  }, (error, stackTrace) {
    debugPrint('LidaPay runZonedGuarded caught unhandled error: $error\n$stackTrace');
  });
}
