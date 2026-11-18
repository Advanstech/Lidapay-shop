class AppConstants {
  AppConstants._();

  /// Live backend: https://api.advansistechnologies.com
  /// Spec: api/openapi.json in this repo (extracted 2026-09-29).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.advansistechnologies.com',
  );

  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration apiConnectTimeout = Duration(seconds: 15);
  static const Duration otpResendCooldown = Duration(minutes: 2);

  static const String appName = 'Lidapay';

  /// Fallback only — the version reported to the backend and shown in the
  /// profile comes from `PackageInfo` (see `DeviceIdentityLoader`). Keep this
  /// in step with `pubspec.yaml` for the cases where the platform probe
  /// fails.
  static const String appVersion = '1.1.3';

  /// Gateway domains the payment checkout page may be opened on. Empty
  /// means any well-formed public HTTPS page (see `isLaunchableCheckoutUrl`).
  /// Pin the list at build time once the backend confirms the gateway hosts:
  /// `--dart-define=CHECKOUT_ALLOWED_HOSTS=example-gateway.com`.
  static List<String> get checkoutAllowedHosts {
    final raw = String.fromEnvironment('CHECKOUT_ALLOWED_HOSTS').trim();
    if (raw.isEmpty) return const <String>[];
    return raw
        .split(',')
        .map((host) => host.trim().toLowerCase())
        .where((host) => host.isNotEmpty)
        .toList(growable: false);
  }

  static const String defaultCountryCode = 'GH';
  static const String defaultCurrency = 'GHS';
  static const String defaultLocale = 'en_GH';
  static const int defaultPageSize = 20;

  /// Deep link the shop checkout + ExpressPay initiation return to. The
  /// payment deep-link handler treats `checkout/callback` as a payment
  /// return, and the backend falls back to `lidapay://redirect-url`.
  static const String shopCheckoutRedirectUrl =
      'lidapay://shop/checkout/callback';

  /// Google Maps key for the live courier driver pin on order tracking.
  /// Pass at build/run time: `--dart-define=GOOGLE_MAPS_API_KEY=<key>`.
  /// The native SDKs read the same key through platform config:
  /// Android via the `GOOGLE_MAPS_API_KEY` manifest placeholder
  /// (android/local.properties or -P flag), iOS via the
  /// `GOOGLE_MAPS_API_KEY` Info.plist build setting. Restrict the key in
  /// Google Cloud Console (Android: SHA-1 + package name; iOS: bundle id)
  /// before shipping — an unrestricted key can be extracted and abused.
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  /// Whether the driver map can render native tiles. Without a key the
  /// tracking card falls back to a coordinates-only view.
  static const bool googleMapsConfigured = googleMapsApiKey != '';
}
