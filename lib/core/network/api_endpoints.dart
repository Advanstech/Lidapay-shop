/// Route paths matching the OpenAPI spec under [AppConstants.apiBaseUrl].
/// See api/ENDPOINTS.md for the full map.
class ApiEndpoints {
  ApiEndpoints._();

  static const String refresh = '/api/v1/auth/refresh';
  static const String loginRequestOtp = '/api/v1/auth/login/request-otp';
  static const String loginVerifyOtp = '/api/v1/auth/login/verify-otp';
  static const String login = '/api/v1/users/login';
  static const String register = '/api/v1/users/register';
  static const String merchantRegister = '/api/v1/merchants/register';
  static const String profile = '/api/v1/users/profile';
  static const String updateProfile = '/api/v1/users/profile/update';
  static const String resendEmailVerification =
      '/api/v1/users/resend-verification-email';
  static const String wallet = '/api/v1/users/wallet/user';
  static const String userAccount = '/api/v1/users/account';
  static const String points = '/api/v1/users/points';
  static const String resetPassword = '/api/v1/users/reset-password';
  static const String confirmResetPassword =
      '/api/v1/users/confirm-reset-password';
  static const String changePassword = '/api/v1/users/change-password';
  static const String confirmPasswordChange =
      '/api/v1/users/confirm-password-change';
  static const String verifyPhone = '/api/v1/users/verify-phone';
  static const String resendPhoneVerification =
      '/api/v1/users/resend-phone-verification-code';

  static const String transactions = '/api/v1/transactions';
  static String userTransactions(String userId) =>
      '/api/v1/transactions/user/$userId';
  static String transactionsStats(String userId) =>
      '/api/v1/transactions/stats/$userId';
  static const String transactionsDateRange = '/api/v1/transactions/date-range';

  static const String lidaValueBalance = '/api/v1/lida-value/balance';
  static const String lidaValueBalanceFallback =
      '/api/v1/lida-value-wallet/balance';
  static const String lidaValueHistory = '/api/v1/lida-value/history';
  static const String lidaValueUse = '/api/v1/lida-value/use';
  static const String lidaValueSend = '/api/v1/lida-value/send';
  static const String lidaValueSell = '/api/v1/lida-value/sell';
  static const String lidaValueConvert = '/api/v1/lida-value/convert';
  static const String lidaValueEligibility = '/api/v1/lida-value/eligibility';

  static const String lidapointsBalance = '/api/v1/lidapoints/balance';
  static const List<String> lidapointsRedeemOptions = [
    '/api/v1/lidapoints/redeem/options',
    '/api/v1/lidapoint/redeem/options',
  ];
  static const List<String> lidapointsRedeemQuote = [
    '/api/v1/lidapoints/redeem/quote',
    '/api/v1/lidapoint/redeem/quote',
  ];
  static const List<String> lidapointsRedeemConfirm = [
    '/api/v1/lidapoints/redeem/confirm',
    '/api/v1/lidapoint/redeem/confirm',
  ];
  static const String lidapointsHistory = '/api/v1/lidapoints/history';

  static const String affiliateSummary = '/api/v1/affiliate/dashboard/summary';

  static const String airtimeTopup = '/api/v1/airtime/topup';
  static const String airtimeTranstatus = '/api/v1/airtime/transtatus';
  static const String internetBundlelist = '/api/v1/internet/bundlelist';
  static const String internetBuydata = '/api/v1/internet/buydata';

  static const String reloadlyPhoneLookup =
      '/api/v1/reload-airtime/phone-lookup';
  static const String reloadlyRecharge = '/api/v1/reload-airtime/recharge';
  static const String reloadlyCountryList = '/api/v1/reloadly/country-list';
  static const String reloadlyFindCountryByCode =
      '/api/v1/reloadly/find-country-by-code';
  static const String reloadlyOperatorsByCountry =
      '/api/v1/reloadly/get-operator-by-code';
  static const String reloadlyOperatorAutodetect =
      '/api/v1/reloadly/operator/autodetect';

  /// Per-operator sender→destination conversion straight from Reloadly
  /// (`GET .../fx-rate?amount=1&currencyCode=USD` answers `localAmount` per
  /// one sender-currency unit plus `localCurrency`).
  static String reloadlyFxRate(int operatorId) =>
      '/api/v1/reloadly/operators/$operatorId/fx-rate';

  /// Global, paginated operator listing — the third route onto the same
  /// Reloadly catalogue, used as a fallback when the per-country lookups
  /// fail (the backend mints its provider token per route).
  static const String reloadlyNetworkOperators =
      '/api/v1/reloadly/network-operators';
  static const String reloadlyDataOperators =
      '/api/v1/reloadly-data/list-operators';
  static const String reloadlyDataAutoDetect =
      '/api/v1/reloadly-data/auto-detect';
  static const String reloadlyDataBuy = '/api/v1/reloadly-data/buy-data';

  static const String advansisInitiate = '/api/v1/advansispay/initiate-payment';
  static const String advansisQuery = '/api/v1/advansispay/query-transaction';

  static const String gtPayServices = '/api/v1/gtpay/services';
  static const String gtPayQuery = '/api/v1/gtpay/query';
  static const String gtPayPay = '/api/v1/gtpay/pay';
  static const String gtPayStatus = '/api/v1/gtpay/status';
  static const String gtPayBanks = '/api/v1/gtpay/banks';

  static const String shopCategories = '/api/v1/shop/categories';
  static const String shopProducts = '/api/v1/shop/products';
  static String shopProduct(String id) => '/api/v1/shop/products/$id';
  static const String shopFeatured = '/api/v1/shop/products/featured';
  static const String shopCart = '/api/v1/shop/cart';
  static const String shopCartAdd = '/api/v1/shop/cart/add';
  static const String shopCartUpdate = '/api/v1/shop/cart/update';
  static const String shopCartRemove = '/api/v1/shop/cart/remove';
  static const String shopCartClear = '/api/v1/shop/cart/clear';
  static const String shopCheckout = '/api/v1/shop/checkout';
  static const String shopOrders = '/api/v1/shop/orders';
  static String shopOrderById(String id) => '/api/v1/shop/orders/$id';

  /// Public lookup by order number (`LPS…`) — returns the full order, so
  /// treat the order number as a shareable tracking id, not a secret.
  static String shopOrderByNumber(String orderNumber) =>
      '/api/v1/shop/orders/number/$orderNumber';
  static String shopOrderTracking(String id) =>
      '/api/v1/shop/orders/$id/tracking';
  static String shopOrderCancel(String id) => '/api/v1/shop/orders/$id/cancel';

  static const String notifications = '/api/v1/notifications';
  static String notification(String id) => '/api/v1/notifications/$id';
  static const String deviceToken = '/api/v1/notifications/device-token';

  static const String recipientEligibility = '/api/v1/recipient/eligibility';
  static String recipientDecision(String decisionId) =>
      '/api/v1/recipient-decisions/$decisionId';
  static String recipientDecisionRespond(String decisionId) =>
      '/api/v1/recipient-decisions/$decisionId/respond';
  static String topupStatus(String topupOrderId) =>
      '/api/v1/topups/$topupOrderId/status';
}
