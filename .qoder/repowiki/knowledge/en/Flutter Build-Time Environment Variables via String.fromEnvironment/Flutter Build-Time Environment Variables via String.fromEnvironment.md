---
kind: configuration_system
name: Flutter Build-Time Environment Variables via String.fromEnvironment
category: configuration_system
scope:
    - '**'
source_files:
    - lib/core/constants/app_constants.dart
    - lib/main.dart
    - android/local.properties
    - ios/Flutter/Local.xcconfig.example
    - docs/GOOGLE_MAPS_SETUP.md
    - pubspec.yaml
---

## Approach

LidaPay does not use a runtime configuration loader (no `.env` parser, no `dotenv`, no JSON/YAML config files). All application-wide settings are supplied at **compile/build time** through Flutter's `--dart-define` mechanism and read at runtime via `String.fromEnvironment`. This keeps secrets out of source control and lets a single codebase target multiple environments (dev/staging/prod) by changing build flags.

## Key Files

- `lib/core/constants/app_constants.dart` — the single source of truth for all Dart-side configuration constants (`apiBaseUrl`, `googleMapsApiKey`, `checkoutAllowedHosts`, timeouts, defaults).
- `lib/main.dart` — app bootstrap: initializes `SharedPreferences`, `SecureSecretStore`, `TokenStore`, Riverpod `ProviderContainer`, and suppresses `debugPrint` in non-debug builds.
- `android/local.properties` — holds the Android-side Google Maps API key (gitignored per `.gitignore`).
- `ios/Flutter/Local.xcconfig.example` — template for the iOS Google Maps key; copied to `Local.xcconfig` (gitignored).
- `docs/GOOGLE_MAPS_SETUP.md` — documents the required `--dart-define=GOOGLE_MAPS_API_KEY=...` invocations for `flutter run` / `flutter build apk/ipa`.
- `pubspec.yaml` — declares dependencies including `shared_preferences`, `flutter_secure_storage`, `firebase_core`, `firebase_messaging`; no config-related packages beyond these.

## Architecture & Conventions

1. **Compile-time constants via `String.fromEnvironment`**
   - `AppConstants.apiBaseUrl` reads `API_BASE_URL` with default `https://api.advansistechnologies.com`.
   - `AppConstants.googleMapsApiKey` reads `GOOGLE_MAPS_API_KEY` with empty-string default.
   - `AppConstants.checkoutAllowedHosts` parses `CHECKOUT_ALLOWED_HOSTS` as a comma-separated list at runtime from the compile-time value.
   - The class constructor is private (`AppConstants._()`) so it cannot be instantiated — it is purely a namespace.

2. **Build-mode branching**
   - `kDebugMode` gates diagnostic logging (`main.dart` overrides `debugPrint` to a no-op in release), verbose HTTP logs (`core/network/api_client.dart`), and feature toggles.
   - No separate debug/release/profile source trees — behavior is selected via `kDebugMode`.

3. **Platform-specific native config**
   - Google Maps keys are injected into both Dart (`--dart-define=GOOGLE_MAPS_API_KEY`) and native layers: Android via `android/local.properties` manifest placeholder, iOS via `ios/Flutter/Local.xcconfig` build setting. The comment in `app_constants.dart` explicitly states the native SDKs read the same key through platform config.

4. **Runtime secrets vs. build-time config**
   - Secrets that must survive on-device (auth tokens, encrypted payment payloads) are stored in `flutter_secure_storage` through `SecureSecretStore`, initialized in `main.dart` before the Riverpod container is created.
   - User preferences (theme, onboarding state) go to `shared_preferences`.
   - There is no runtime secret refresh or remote config service.

5. **Riverpod ProviderContainer overrides**
   - `main.dart` constructs a single `ProviderContainer` and injects `sharedPrefsProvider`, `tokenStoreProvider`, `secretStoreProvider`, and `deviceIdentityProvider` via `overrides`, making them globally available to features.

6. **No environment file format**
   - The repo contains no `.env`, `.env.example`, YAML/TOML config, or `application.properties`. The only example env-like file is `tool/courier-orders/.env.example` which belongs to a standalone Node.js dev tool, not the Flutter app.

## Conventions & Constraints

- **All Dart-side configuration goes through `AppConstants`**: new build-time values should be added as static getters using `String.fromEnvironment(...)` rather than hard-coded strings scattered across features.
- **Sensitive keys are never committed**: `android/local.properties` and `ios/Flutter/Local.xcconfig` are gitignored; the iOS template lives under `Local.xcconfig.example` with instructions to copy and fill it locally.
- **Google Maps key is mandatory for the driver tracking card**: `AppConstants.googleMapsConfigured` is derived from whether the key is non-empty, and screens like `delivery_pin_screen.dart` gate map rendering behind this flag.
- **Checkout URL host allowlist is enforced at build time**: `CHECKOUT_ALLOWED_HOSTS` is parsed into an immutable list; when empty, `isLaunchableCheckoutUrl` permits any well-formed public HTTPS page (see `core/utils/url_guard.dart`).
- **Release builds strip diagnostics**: `main.dart` replaces `debugPrint` with a no-op when `!kDebugMode`, preventing URLs and identifiers from leaking to device logs.
- **Default backend URL is baked in**: if `API_BASE_URL` is not defined, the app targets `https://api.advansistechnologies.com` — there is no runtime override path.