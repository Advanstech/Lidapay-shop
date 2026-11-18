---
kind: dependency_management
name: Multi-Platform Dependency Management (Flutter pub, Android Gradle, CocoaPods, Node)
category: dependency_management
scope:
    - '**'
source_files:
    - pubspec.yaml
    - pubspec.lock
    - android/build.gradle.kts
    - android/settings.gradle.kts
    - android/app/build.gradle.kts
    - ios/Podfile
    - ios/Podfile.lock
    - tool/courier-orders/package.json
    - tool/courier-orders/package-lock.json
---

## Overview

LidaPay is a multi-platform Flutter application that manages dependencies across four toolchains:

1. **Dart/Flutter** — `pubspec.yaml` + `pubspec.lock`
2. **Android** — Gradle Kotlin DSL (`android/build.gradle.kts`, `android/settings.gradle.kts`, `android/app/build.gradle.kts`) resolving Maven repos
3. **iOS** — CocoaPods (`ios/Podfile` + `ios/Podfile.lock`) resolving the Apple trunk spec repo
4. **Node.js dev tooling** — `tool/courier-orders/package.json` + `package-lock.json` (and a small `tool/livecheck/` package)

There is no monorepo dependency orchestrator (no Lerna, Turborepo, or Bazel); each platform resolves its own graph independently.

## Dart / Flutter Dependencies

- Declaration: `pubspec.yaml` under `dependencies:` and `dev_dependencies:`.
- Version pinning: all third-party packages use caret ranges (e.g. `flutter_riverpod: ^2.6.1`, `dio: ^5.8.0`, `firebase_core: ^5.1.0`). The SDK constraint is `environment.sdk: ^3.13.4`.
- Lockfile: `pubspec.lock` is committed and pins exact resolved versions for reproducible builds.
- Private registry: `publish_to: 'none'` disables publishing to pub.dev; no custom `pubspec_overrides.yaml` or `pubspec.yaml` `dependency_overrides` are present in the root, so there is no local workspace overlay.
- No vendored Dart packages — everything comes from `pub.dev` at resolution time.
- App version is declared as `version: 1.1.3+34` (semantic version + build number).

## Android Dependencies

- Repositories are declared in two places:
  - `android/build.gradle.kts`: `google()` and `mavenCentral()`.
  - `android/settings.gradle.kts` pluginManagement block: `google()`, `mavenCentral()`, `gradlePluginPortal()`.
- Plugin versions are pinned in `settings.gradle.kts` via the `plugins { ... }` block:
  - `dev.flutter.flutter-plugin-loader` version `1.0.0`
  - `com.android.application` version `9.1.0`
  - `org.jetbrains.kotlin.android` version `2.4.0`
  - `com.google.gms.google-services` version `4.4.2`
- Gradle wrapper is used (`gradlew`, `gradle/wrapper/gradle-wrapper.jar`, `gradle/wrapper/gradle-wrapper.properties`); no explicit `distributionUrl` override was inspected but the wrapper files exist.
- No private Maven repository or `GRADLE_OPTS`/`GRADLE_USER_HOME` configuration is visible in the checked-in tree.
- Build output is redirected to a shared `build/` directory at the repo root via `rootProject.layout.buildDirectory = ../../build`.

## iOS Dependencies

- Managed by CocoaPods via `ios/Podfile`. It sets `platform :ios, '15.0'` and uses `use_frameworks!`.
- Flutter plugins are auto-installed through `flutter_install_all_ios_pods` (from `packages/flutter_tools/bin/podhelper`), which reads `.symlinks/plugins/` — Flutter's standard symlink-based plugin layout.
- Native third-party pods (Firebase, Google Maps, nanopb, PromisesObjC, GoogleUtilities) are pulled from the CocoaPods trunk spec repo (see `SPEC REPOS: trunk` in `Podfile.lock`).
- `ios/Podfile.lock` is committed and pins every pod plus transitive dependency with checksums under `SPEC CHECKSUMS`, ensuring deterministic native builds.
- CocoaPods analytics is disabled via `ENV['COCOAPODS_DISABLE_STATS'] = 'true'` in `Podfile` to avoid synchronous network calls during build.
- No private Podspec repo or `source` override is configured — only the default trunk is used.

## Node.js Tooling Dependencies

- `tool/courier-orders/package.json` declares runtime deps `jsonwebtoken: ^9.0.3` and `mongodb: ^7.8.0` with a lockfile `package-lock.json`.
- `tool/livecheck/package.json` exists alongside its own `package-lock.json`.
- These are standalone scripts, not part of the app bundle.

## Conventions Observed

- Each platform owns its own manifest and lockfile; there is no cross-toolchain version coordination.
- Third-party versions are expressed as caret ranges in manifests (`^x.y.z`) while lockfiles commit exact resolved versions and checksums.
- Flutter plugins are consumed through the standard Flutter plugin mechanism (symlinked under `.dart_tool/` and `ios/.symlinks/plugins/`); they are not vendored as source code.
- No private registries (custom pub.dev mirror, private Maven repo, or private CocoaPods repo) are configured in the checked-in tree.
- The app itself is marked non-publishable (`publish_to: 'none'`), indicating it is treated as an internal/private package.
- Android plugin versions are centralized in `settings.gradle.kts` rather than scattered per-subproject.