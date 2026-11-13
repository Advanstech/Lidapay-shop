import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Brand palette sampled from the Lidapay logo — magenta/crimson + deep navy.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFFE31C5F);
  static const Color primaryDark = Color(0xFFB8144B);
  static const Color primaryTint = Color(0xFFFDE7EF);
  static const Color onDarkPrimary = Color(0xFFFF4D84);
  static const Color violet = Color(0xFF7B2FF7);

  static const Color navy = Color(0xFF2A2550);
  static const Color navyDark = Color(0xFF1D1939);
  static const Color ink = Color(0xFF17143A);

  static const Color success = Color(0xFF1FA97A);
  static const Color warning = Color(0xFFF5A623);
  static const Color error = Color(0xFFE5484D);

  static const Color gold = Color(0xFFF6C453);

  // OLED dark ramp.
  static const Color darkScaffold = Color(0xFF0C0A1C);
  static const Color darkSurface = Color(0xFF161330);
  static const Color darkInput = Color(0xFF221E48);

  // Porcelain light ramp.
  static const Color lightScaffold = Color(0xFFFAF9FD);
  static const Color lightInput = Color(0xFFF1F0F7);

  /// Magenta → violet sweep used by CTAs, logo mark and accents.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, violet],
  );

  /// Deep ink sweep used by the hero wallet card.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF33295E), Color(0xFF1B163E)],
  );
}

/// Shared shape scale — every surface, tile and chip snaps to these radii.
abstract final class AppRadii {
  static const double card = 28;
  static const double tile = 20;
  static const double chip = 14;
  static const double button = 18;
}

abstract final class AppShadows {
  /// Soft ambient shadow for surface cards. Dark mode leans on borders,
  /// so it only deepens the glow there.
  static List<BoxShadow> card(bool isDark) => [
    BoxShadow(
      color: isDark
          ? const Color(0x66000000)
          : AppColors.navy.withValues(alpha: 0.07),
      blurRadius: 26,
      offset: const Offset(0, 12),
    ),
  ];

  /// Brand glow under gradient surfaces (CTAs, center dock action).
  static List<BoxShadow> glow(
    Color color, {
    double alpha = 0.32,
    double blur = 26,
  }) => [
    BoxShadow(
      color: color.withValues(alpha: alpha),
      blurRadius: blur,
      offset: const Offset(0, 12),
    ),
  ];
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: isDark ? AppColors.onDarkPrimary : AppColors.primary,
          secondary: AppColors.navy,
          surface: isDark ? AppColors.darkSurface : Colors.white,
          onSurface: isDark ? const Color(0xFFF2F0FA) : AppColors.ink,
          onSurfaceVariant: isDark
              ? const Color(0xFFA9A3CC)
              : const Color(0xFF5F5A7D),
          error: AppColors.error,
          surfaceContainerHighest: isDark
              ? AppColors.darkInput
              : AppColors.lightInput,
        );

    final scaffoldBg = isDark
        ? AppColors.darkScaffold
        : AppColors.lightScaffold;

    final baseText = ThemeData(
      brightness: brightness,
      useMaterial3: true,
    ).textTheme;

    final textTheme = baseText
        .apply(fontFamily: 'Plus Jakarta Sans')
        .copyWith(
          labelLarge: baseText.labelLarge?.copyWith(
            fontFamily: 'Plus Jakarta Sans',
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scaffoldBg,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: isDark
              ? const BorderSide(color: Colors.white10)
              : BorderSide.none,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          fontSize: 14.5,
        ),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        border: _inputBorder(Colors.transparent),
        enabledBorder: _inputBorder(Colors.transparent),
        focusedBorder: _inputBorder(scheme.primary, width: 1.8),
        errorBorder: _inputBorder(AppColors.error),
        focusedErrorBorder: _inputBorder(AppColors.error, width: 1.8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white10 : const Color(0xFFECEAF4),
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF120F26) : Colors.white,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        height: 72,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
}
