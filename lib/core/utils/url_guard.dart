import '../constants/app_constants.dart';

/// The checkout page URL is chosen by the backend, so it is untrusted input
/// to the launcher: a spoofed or compromised response must not be able to
/// open a plaintext page, an arbitrary app-scheme intent, or an internal host.
///
/// By default any well-formed public HTTPS page is allowed so the live
/// gateway keeps working. Set `CHECKOUT_ALLOWED_HOSTS` at build time (for
/// example `--dart-define=CHECKOUT_ALLOWED_HOSTS=expresspay.com`) to pin the
/// launch to the gateway domains from the backend docs.
bool isLaunchableCheckoutUrl(Uri uri) {
  if (uri.scheme != 'https') return false;
  if (uri.host.isEmpty) return false;
  if (uri.userInfo.isNotEmpty) return false;

  final host = uri.host.toLowerCase();
  if (host == 'localhost' || host.endsWith('.local')) return false;

  final allowed = AppConstants.checkoutAllowedHosts;
  if (allowed.isEmpty) return true;
  return allowed.any((domain) => host == domain || host.endsWith('.$domain'));
}
