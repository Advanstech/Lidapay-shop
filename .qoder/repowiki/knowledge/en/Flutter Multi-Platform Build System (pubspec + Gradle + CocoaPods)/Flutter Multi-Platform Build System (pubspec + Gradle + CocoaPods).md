---
kind: build_system
name: Flutter Multi-Platform Build System (pubspec + Gradle + CocoaPods)
category: build_system
scope:
    - '**'
source_files:
    - pubspec.yaml
    - pubspec.lock
    - android/build.gradle.kts
    - android/app/build.gradle.kts
    - android/key.properties
    - android/local.properties
    - android/gradle.properties
    - android/settings.gradle.kts
    - ios/Podfile
    - ios/Podfile.lock
    - ios/Runner.xcworkspace/contents.xcworkspacedata
    - web/index.html
    - web/manifest.json
    - tool_static_server.mjs
    - tool/serve_web.js
    - tool/generate_icons.py
---

## What system/approach is used

The LidaPay app is a single Flutter package (`pubspec.yaml`, `name: lidapay_app`) that composes three native targets — Android, iOS, and Web — through the standard Flutter toolchain. There is no custom Makefile, Dockerfile, or CI pipeline in this repository; build orchestration is delegated to:

- **Flutter SDK** (`environment.sdk: ^3.13.4` in `pubspec.yaml`) for dependency resolution (`flutter pub get`), asset/font bundling, and cross-compilation.
- **Gradle (Kotlin DSL)** under `android/` for the Android APK/AAB build, signing, ProGuard/R8 shrinking, and Google Services integration.
- **CocoaPods** under `ios/Podfile` for iOS native dependencies (Firebase, Google Maps).
- **Xcode workspace** (`ios/Runner.xcworkspace`) for the iOS target.
- **Web shell** (`web/index.html`, `web/manifest.json`) plus static legal pages served via `tool_static_server.mjs` / `tool/serve_web.js`.

No GitHub Actions, Jenkins, Fastlane, or Docker configuration exists at the repo root (`.github/` directory is absent). Release artifacts are produced locally by the developer using the Flutter CLI against the configured Gradle/Xcode projects.

## Key files and packages

- `pubspec.yaml` — single source of truth for Dart dependencies, version (`1.1.3+34`), assets, fonts, and `flutter_launcher_icons` config.
- `pubspec.lock` — pinned dependency tree.
- `android/build.gradle.kts` — root Gradle script; redirects all build output to the shared `build/` directory at repo root and registers a `clean` task.
- `android/app/build.gradle.kts` — per-app Gradle config: namespace, compile/target/minSdk from Flutter, `dev.flutter.flutter-gradle-plugin`, Google Services plugin, release signing, minify/shrink/proguard, NDK symbol table, Kotlin JVM 17.
- `android/key.properties` — keystore alias/passwords pointing to `../lidapay-upload.jks` (keystore file committed alongside).
- `android/local.properties` — local machine paths (Android SDK, etc.).
- `android/gradle.properties` — Gradle settings.
- `android/settings.gradle.kts` — Gradle settings.
- `ios/Podfile` — CocoaPods manifest pinning platform iOS 15.0, disabling CocoaPods analytics (`COCOAPODS_DISABLE_STATS=true`), wiring Flutter pod helper.
- `ios/Podfile.lock` — locked CocoaPods dependency tree.
- `ios/Runner.xcodeproj` / `ios/Runner.xcworkspace` — Xcode project/workspace.
- `web/index.html`, `web/manifest.json` — web entry point and PWA manifest.
- `tool_static_server.mjs`, `tool/serve_web.js` — dev-only static file servers for the web shell.
- `tool/generate_icons.py` — icon generation utility.

## Architecture and conventions

### Versioning
Version is declared once in `pubspec.yaml` as `version: 1.1.3+34` (semantic version + build number). The comment in `pubspec.yaml` documents the mapping: `build-name` → Android `versionName` / iOS `CFBundleShortVersionString`; `build-number` → Android `versionCode` / iOS `CFBundleVersion`. `android/app/build.gradle.kts` reads these via `flutter.versionCode` / `flutter.versionName`.

### Dependency management
- Dart/Flutter deps: managed via `pubspec.yaml` with caret ranges (e.g. `dio: ^5.8.0`, `firebase_core: ^5.1.0`). `pubspec.lock` pins exact transitive versions.
- Android native deps: managed by Gradle (`com.android.application`, `dev.flutter.flutter-gradle-plugin`, `com.google.gms.google-services`, `desugar_jdk_libs:2.1.4`).
- iOS native deps: managed by CocoaPods (`Podfile` + `Podfile.lock`).
- No vendoring of Dart sources; plugins are resolved from pub.dev.

### Signing & secrets
- Android release signing is driven by `android/key.properties` (loaded via `Properties()` in `app/build.gradle.kts`) referencing `../lidapay-upload.jks` and `upload_cert.pem` committed at repo root. Keystore passwords are stored in plain text in `key.properties` (and also visible in `KEYSTORE_INFO_SECURE.txt` at repo root).
- Google Maps API key for Android is injected through a precedence chain in `app/build.gradle.kts`: `-P GOOGLE_MAPS_API_KEY` > env var `GOOGLE_MAPS_API_KEY` > `local.properties.GOOGLE_MAPS_API_KEY`.

### Build outputs
- All Gradle build directories are redirected to the shared `build/` folder at the repo root via `rootProject.layout.buildDirectory.dir("../../build")` in `android/build.gradle.kts`, so Android, iOS (via Flutter), and any other subprojects share one output tree.
- Android release builds enable R8 (`isMinifyEnabled = true`, `isShrinkResources = true`) with `proguard-rules.pro` and set `ndk.debugSymbolLevel = "SYMBOL_TABLE"` for Play Console crash deobfuscation.

### Assets & icons
- Fonts (Inter, Plus Jakarta Sans, Sora) and images live under `assets/fonts/` and `assets/images/`, declared in `pubspec.yaml` under `flutter.fonts` and `flutter.assets`.
- App icons are generated via `flutter_launcher_icons` using `assets/icons/app_icon_master_1024.png` as the source, producing adaptive icons for Android and standard icons for iOS.

### Platform shells
- Android: `android/app/src/main/kotlin/com/advansistechnologies/lidapay_app/MainActivity.kt` is the Kotlin entry point; `google-services.json` wires Firebase.
- iOS: `ios/Runner/AppDelegate.swift` + `SceneDelegate.swift` are the UIKit entry points; Firebase and Google Maps are integrated via CocoaPods.
- Web: `web/index.html` serves the Flutter web build alongside static legal pages (`privacy-policy.html`, `terms-of-service.html`, `payments-refunds.html`, `kyc-anti-fraud.html`, `account-deletion.html`).

### Testing
- Unit/widget tests live under `test/` and are run via `flutter test` (no separate test runner script).
- `analysis_options.yaml` configures `flutter_lints` for static analysis.

## Conventions and constraints

- **Single-version source**: Application version is defined only in `pubspec.yaml` and consumed by both Android (`flutter.versionCode` / `flutter.versionName`) and iOS (via Flutter's mapping documented in the `pubspec.yaml` comments); there is no independent version declaration in Gradle or Xcode.
- **Java/Kotlin 17**: `android/app/build.gradle.kts` enforces `sourceCompatibility = JavaVersion.VERSION_17`, `targetCompatibility = JavaVersion.VERSION_17`, and `kotlin { compilerOptions { jvmTarget = JVM_17 } }`.
- **Release hardening on Android**: `release` build type always enables minification, resource shrinking, ProGuard rules, and NDK symbol tables — not optional flags.
- **Google Maps key injection order**: The Android build resolves `GOOGLE_MAPS_API_KEY` strictly in the order `-P` property → environment variable → `local.properties` value, defaulting to empty string if none is provided.
- **Shared build directory**: All Gradle subprojects write into `build/<project>/` at the repo root, enforced by the root `android/build.gradle.kts` overriding `rootProject.layout.buildDirectory`.
- **iOS platform minimum**: `ios/Podfile` pins `platform :ios, '15.0'`.
- **CocoaPods analytics disabled**: `ENV['COCOAPODS_DISABLE_STATS'] = 'true'` is set in `Podfile` to avoid synchronous network calls during `pod install`.
- **No CI/Docker**: There is no `.github/workflows`, `Dockerfile`, `Makefile`, or automated release pipeline checked into the repository; builds are intended to be executed manually via `flutter build apk|aab|ios|web`.
- **Keystore committed**: The release keystore `android/lidapay-upload.jks` and its password file `android/key.properties` are committed to the repository, making signing reproducible without external secret management.