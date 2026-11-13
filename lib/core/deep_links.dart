import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:go_router/go_router.dart';

import 'router/app_router.dart';

/// Routes `lidapay://` payment-return URIs into the app. Started once after
/// the session restore in main; URIs arriving while signed out are parked
/// until the session exists, then delivered once.
class PaymentDeepLinkHandler {
  PaymentDeepLinkHandler({
    AppLinks? links,
    required GoRouter router,
    required bool Function() hasSession,
  }) : _links = links ?? AppLinks(),
       _router = router,
       _hasSession = hasSession;

  final AppLinks _links;
  final GoRouter _router;
  final bool Function() _hasSession;

  StreamSubscription<Uri>? _sub;
  Uri? _parked;

  Future<void> start() async {
    try {
      _sub = _links.uriLinkStream.listen(_dispatch, onError: (_) {});
      final initial = await _links.getInitialLink();
      if (initial != null) _dispatch(initial);
    } catch (_) {
      // Missing plugin channels (tests, unsupported platforms) must not
      // block startup — payments simply lose the instant-return path.
    }
  }

  void _dispatch(Uri uri) {
    // Password links need no session — the emailed token is the
    // authority, and the reset flow exists precisely for signed-out
    // users. Route them immediately, never park them.
    if (_isPasswordLink(uri)) {
      _routePasswordLink(uri);
      return;
    }
    if (!_isPaymentReturn(uri)) return;
    if (!_hasSession()) {
      _parked = uri;
      return;
    }
    _routeToCallback(uri);
  }

  /// Called when auth state changes so a link that arrived while signed
  /// out is delivered once the session exists.
  void flush() {
    final uri = _parked;
    if (uri == null || !_hasSession()) return;
    _parked = null;
    _routeToCallback(uri);
  }

  /// The backend fallback is `lidapay://redirect-url?…`; newer builds emit
  /// `lidapay://payments/callback?…` and the shop handoff mentions
  /// `lidapay://shop/checkout/callback`. All three are payment returns.
  static bool _isPaymentReturn(Uri uri) {
    if (uri.scheme != 'lidapay') return false;
    final host = uri.host;
    final path = uri.path;
    return host == 'redirect-url' ||
        host == 'payments' ||
        host == 'payment' ||
        path.contains('redirect-url') ||
        path.contains('checkout/callback');
  }

  /// `lidapay://reset-password?token=…` / `lidapay://verify-password-change?token=…`
  /// (host-style) or the path-style `lidapay:///reset-password?token=…`.
  /// The backend may also emit plain https APP_URL links — those arrive
  /// through go_router directly, not this stream.
  static bool _isPasswordLink(Uri uri) {
    if (uri.scheme != 'lidapay') return false;
    final host = uri.host;
    final path = uri.path;
    return host == 'reset-password' ||
        host == 'verify-password-change' ||
        path.contains('reset-password') ||
        path.contains('verify-password-change');
  }

  void _routePasswordLink(Uri uri) {
    final isReset =
        uri.host == 'reset-password' || uri.path.contains('reset-password');
    final route = isReset
        ? AppRoutes.resetPassword
        : AppRoutes.verifyPasswordChange;
    final token = uri.queryParameters['token'];
    _router.push(
      Uri(
        path: route,
        queryParameters: {
          if (token != null && token.isNotEmpty) 'token': token,
        },
      ).toString(),
    );
  }

  void _routeToCallback(Uri uri) {
    final params = uri.queryParameters;
    final orderId = params['orderId'] ?? params['order-id'];
    final token = params['token'];
    final status = params['status'];
    final errorMessage = params['errorMessage'] ?? params['error_message'];

    _router.push(
      Uri(
        path: AppRoutes.paymentCallback,
        queryParameters: {
          if (status != null) 'status': status,
          if (orderId != null && orderId.isNotEmpty) 'orderId': orderId,
          // The callback token is never forwarded — the saved token is the
          // verification authority; presence just unlocks verification.
          if (token != null && token.isNotEmpty) 'hasToken': '1',
          if (errorMessage != null && errorMessage.isNotEmpty)
            'errorMessage': errorMessage,
        },
      ).toString(),
    );
  }

  void dispose() => _sub?.cancel();
}
