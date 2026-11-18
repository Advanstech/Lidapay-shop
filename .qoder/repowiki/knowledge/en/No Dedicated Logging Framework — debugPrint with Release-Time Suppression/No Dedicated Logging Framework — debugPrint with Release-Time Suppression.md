---
kind: logging_system
name: No Dedicated Logging Framework — debugPrint with Release-Time Suppression
category: logging_system
scope:
    - '**'
source_files:
    - lib/main.dart
    - lib/core/network/api_client.dart
    - lib/core/location/location_service.dart
    - lib/core/notifications/push_notification_service.dart
    - pubspec.yaml
---

# Logging System

## What system/approach is used

The LidaPay Flutter app does **not** use a dedicated logging framework. There are no logging dependencies in `pubspec.yaml` (no `logger`, `logging`, `pretty`, `loguru`, or similar), and no `import` of any logging package anywhere in the codebase. All diagnostic output goes through Flutter's built-in `debugPrint` from `package:flutter/foundation.dart`. There is no log-level abstraction, no structured log records, no sink/router, and no external log aggregation.

## Key files and packages

- `lib/main.dart` — global initialization: suppresses `debugPrint` in release builds, installs `FlutterError.onError`, `PlatformDispatcher.instance.onError`, and `runZonedGuarded` error handler; all emit via `debugPrint`.
- `lib/core/network/api_client.dart` — HTTP request/response diagnostics emitted via `debugPrint`.
- `lib/core/location/location_service.dart` — geocoding / location lookup failures logged via `debugPrint`.
- `lib/core/notifications/push_notification_service.dart` — Firebase messaging / local notification lifecycle events logged via `debugPrint`.

## Architecture and conventions

1. **Single sink (`debugPrint`)** — Every diagnostic call site uses `debugPrint('...')`; there is no logger class, no module-scoped logger instance, and no wrapper around `debugPrint`.
2. **Release-time suppression** — In `lib/main.dart` lines 24–28, when `!kDebugMode` the global `debugPrint` function is replaced with an empty no-op:
   ```dart
   if (!kDebugMode) {
     debugPrint = (String? message, {int? wrapWidth}) {};
   }
   ```
   This means production builds emit zero diagnostic output, regardless of where `debugPrint` is called. The comment above it states the rationale: "Release builds must not write diagnostics (URLs, identifiers) to the device log; release crash reporting is the field channel."
3. **Global error capture instead of log levels** — Unhandled exceptions are funneled through three mechanisms, all writing via `debugPrint`:
   - `FlutterError.onError` for widget/rendering errors.
   - `PlatformDispatcher.instance.onError` for platform dispatch errors (returns `true` to avoid crashing the host process).
   - `runZonedGuarded` callback for uncaught async errors.
4. **Human-readable messages, no structured fields** — Log messages are plain interpolated strings such as `'Token store load non-fatal warning: $e'`, `'LidaPay Caught FlutterError: ${details.exceptionAsString()}'`, `'Background message handler init warning: $e'`. No JSON serialization, no correlation IDs, no timestamp or level prefix is added by the application.
5. **No per-module loggers** — Services like `api_client.dart`, `location_service.dart`, and `push_notification_service.dart` call `debugPrint` directly rather than going through a shared logger singleton.

## Conventions and constraints

- **Observed convention**: All application diagnostics go through `debugPrint`; no other logging API is imported or used.
- **Enforced rule (code-enforced)**: In release builds (`!kDebugMode`), `debugPrint` is globally reassigned to a no-op at startup in `lib/main.dart`, so no diagnostic output can escape the process. This is enforced by the runtime reassignment of the top-level `debugPrint` symbol.
- **Enforced rule (dependency manifest)**: `pubspec.yaml` contains no logging dependency under `dependencies` or `dev_dependencies`; adding one would require an explicit change to the manifest.
- **Constraint on content**: Because release builds suppress `debugPrint`, any sensitive data (URLs, tokens, device identifiers) that might leak into logs is effectively blocked in production — this is the stated design intent in the comment at `lib/main.dart:24-26`.