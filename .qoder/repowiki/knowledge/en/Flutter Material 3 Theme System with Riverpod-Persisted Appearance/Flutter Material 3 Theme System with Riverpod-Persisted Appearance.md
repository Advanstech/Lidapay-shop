---
kind: frontend_style
name: Flutter Material 3 Theme System with Riverpod-Persisted Appearance
category: frontend_style
scope:
    - '**'
source_files:
    - lib/core/theme/app_theme.dart
    - lib/core/providers/theme_provider.dart
    - lib/app.dart
    - pubspec.yaml
    - web/legal.css
---

## What system/approach is used

The LidaPay app is a single Flutter application. Its UI styling is built entirely on **Flutter Material 3** (`useMaterial3: true`) with a custom `ThemeData` factory, not on any CSS framework (no Tailwind, no SCSS). The only CSS in the repository lives under `web/legal.css`, which styles the static legal pages served alongside the Flutter web build.

Key packages involved:
- `flutter/material.dart` — Material 3 theme, widgets, and color system.
- `flutter_riverpod` — state management for the persisted theme mode.
- `shared_preferences` — persistence of the user's light/dark/system choice.
- Custom fonts registered via `pubspec.yaml`: **Plus Jakarta Sans** (weights 400–800).

No external design-system package (e.g. `fluent_ui`, `supernova`, `tokens`) is used; all tokens are hand-authored in Dart.

## Key files and packages

- `lib/core/theme/app_theme.dart` — central theme definition: brand palette, radii, shadows, gradients, and the `AppTheme.light()` / `AppTheme.dark()` factories that produce `ThemeData`.
- `lib/core/providers/theme_provider.dart` — Riverpod `StateNotifierProvider` (`themeModeProvider`) exposing the persisted `ThemeMode` (light / dark / system) backed by `SharedPreferences`.
- `lib/app.dart` — wires `MaterialApp.router` with `theme`, `darkTheme`, and `themeMode` from the provider; also configures `SystemUiOverlayStyle` for status/navigation bar contrast.
- `pubspec.yaml` — declares `uses-material-design: true`, registers the `Plus Jakarta Sans` font family, and lists UI-related dependencies (`shimmer`, `cached_network_image`, `smooth_page_indicator`).
- `web/legal.css` — standalone stylesheet for the legal PWA pages (privacy, terms, payments-refunds, kyc-anti-fraud, account-deletion), using CSS custom properties and modern layout (`clamp`, `min()`, `gap`).
- `assets/fonts/` — bundled Inter, Sora, and Plus Jakarta Sans TTFs (Inter/Sora appear to be candidates; Plus Jakarta Sans is the active one).

## Architecture and conventions

### Design tokens live in Dart

`AppColors` (in `app_theme.dart`) is a final class holding every semantic color as `static const Color` values: primary magenta (`#FFE31C5F`), violet, navy, ink, success/warning/error/gold, plus per-mode scaffold/surface/input ramps (`darkScaffold`, `darkSurface`, `darkInput`, `lightScaffold`, `lightInput`). Two shared `LinearGradient`s (`brandGradient` from primary→violet, `heroGradient` from deep navy tones) are defined here too.

`AppRadii` centralizes corner radii: card = 28, tile = 20, chip = 14, button = 18. `AppShadows` provides reusable `BoxShadow` helpers for surface cards and brand glows.

### ThemeData construction

`AppTheme._base(Brightness)` builds a `ColorScheme.fromSeed(seedColor: AppColors.primary)` and then overrides key swatches (`surface`, `onSurface`, `onSurfaceVariant`, `surfaceContainerHighest`) based on brightness. Text uses `TextTheme.apply(fontFamily: 'Plus Jakarta Sans')` with an extra bold `labelLarge`. Component themes are centralized:

- `AppBarTheme` — flat, centered title, elevation 0.
- `CardThemeData` — 24px radius, border in dark mode only.
- `InputDecorationTheme` — filled inputs with rounded borders, focus/error states driven by `primary` and `error`.
- `ElevatedButtonThemeData` — 56px height, 18px radius, primary background.
- `SnackBarThemeData` — floating, 12px radius.
- `NavigationBarThemeData` — 72px height, tinted indicator.
- `BottomSheetThemeData` — top-rounded 28px corners.
- `DialogThemeData` — 24px radius.

Page transitions are platform-specific: Cupertino builders on iOS/macOS, zoom builder on Android.

### Theme mode persistence

`ThemeModeNotifier` extends `StateNotifier<ThemeMode>` and stores the value under the key `'theme_mode'` in `SharedPreferences`. On first load it restores the saved mode; a `_userTouched` flag prevents overwriting a user selection made while prefs were still loading. The default is `ThemeMode.system`.

### Web shell styling

The Flutter web shell is configured through `MaterialApp.router` in `lib/app.dart`. The static legal HTML pages under `web/` use their own minimal CSS (`web/legal.css`) with a `:root` color scheme, system font stack, gradient header, responsive `clamp()` typography, and a `prefers-reduced-motion` media query for smooth scrolling.

## Conventions and constraints

Observed conventions (descriptive):
- All colors go through `AppColors`; raw hex literals are avoided in feature code.
- Corner radii are taken from `AppRadii` rather than ad-hoc numbers.
- Both light and dark themes are produced from the same `_base` factory so they stay synchronized.
- The app font is consistently set via `TextTheme.apply(fontFamily: 'Plus Jakarta Sans')` inside the theme factory.
- Theme mode is consumed via the Riverpod `themeModeProvider` and passed into `MaterialApp.themeMode`.
- Native system bars are styled through `SystemUiOverlayStyle` in `lib/app.dart` to match the current brightness.

Enforced rules (from authoritative sources):
- `useMaterial3: true` is set in both the base `ThemeData` and the `ThemeData` returned by `_base` (`lib/core/theme/app_theme.dart` lines 117 and 131), so Material 3 is the enforced UI paradigm.
- `MaterialApp.router` is the single entry point for theming (`lib/app.dart` lines 194–201); `theme`, `darkTheme`, and `themeMode` are supplied there, making this the canonical place where appearance is configured.
- Fonts are declared exclusively in `pubspec.yaml` under `flutter.fonts` (family `Plus Jakarta Sans`, weights 400–800); the theme references the same family name, tying asset registration to runtime usage.
- The legal web pages are styled independently of the Flutter theme via `web/legal.css`, which sets its own `color-scheme: light` and does not inherit Flutter's theme.