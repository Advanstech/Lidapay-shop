import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import 'activity_feed.dart';
import 'dashboard_models.dart';
import 'dashboard_repository.dart';

/// Live dashboard data. The wallet card aggregates three endpoints
/// (users/wallet/user, users/points, lida-value/balance); points and Lida
/// Value failures degrade to zero rather than failing the whole card.
class RemoteDashboardRepository implements DashboardRepository {
  RemoteDashboardRepository(this._api, this._userId);

  final ApiClient _api;
  final String? _userId;

  bool get _hasUserId => _userId != null && _userId.isNotEmpty;

  @override
  Future<WalletSummary> getWalletSummary() async {
    // The wallet, Lida Value, and points endpoints are all JWT-scoped — no
    // user id is required, so the card renders before the profile lands.
    // Each section fails independently: a 500 on the wallet document must
    // not blank the whole dashboard.
    final results = await Future.wait<Object?>([
      _fetchWallet(),
      _fetchLidaValueUnits(),
      _fetchPoints(),
    ]);
    final wallet = results[0] as Map<String, dynamic>?;
    return WalletSummary(
      balance: _asDouble(
        wallet?['balance'] ??
            wallet?['amount'] ??
            wallet?['value'] ??
            wallet?['walletBalance'],
      ),
      currency: (wallet?['currency'] ?? wallet?['currencyCode'] ?? 'GHS')
          .toString(),
      lidaValueUnits: results[1] as double,
      lidaPoints: results[2] as int,
      walletAvailable: wallet != null,
    );
  }

  Future<Map<String, dynamic>?> _fetchWallet() async {
    try {
      return await _api.get(ApiEndpoints.wallet);
    } on ApiException catch (e) {
      if (e.statusCode == 401) rethrow;
      // Users without a wallet document get a 500 here; the account
      // endpoint still exposes a usable balance for them.
      return _fetchAccountWallet();
    }
  }

  /// GET /api/v1/users/account — returns {id, userId, balance,
  /// transactions[]}; mapped onto the wallet shape the summary expects.
  Future<Map<String, dynamic>?> _fetchAccountWallet() async {
    try {
      final data = await _api.get(ApiEndpoints.userAccount);
      return {
        'balance':
            data['balance'] ?? data['amount'] ?? data['walletBalance'] ?? 0,
        'currency': data['currency'] ?? 'GHS',
      };
    } catch (_) {
      // Any failure here leaves the wallet card degraded — never fatal.
      return null;
    }
  }

  Future<double> _fetchLidaValueUnits() async {
    // `lida-value-wallet/balance` is the spec's fallback pair for the main
    // route — both return the same loosely-shaped balance object.
    for (final path in const [
      ApiEndpoints.lidaValueBalance,
      ApiEndpoints.lidaValueBalanceFallback,
    ]) {
      try {
        final raw = await _api.getRaw(path);
        if (raw is num) return raw.toDouble();
        if (raw is Map) {
          final data = Map<String, dynamic>.from(raw);
          for (final key in const [
            'totalValueUnits',
            'balance',
            'valueUnits',
            'value',
            'amount',
          ]) {
            final v = data[key];
            if (v != null) return _asDouble(v);
          }
        }
      } on ApiException catch (e) {
        if (e.statusCode == 401) rethrow;
        continue;
      }
    }
    return 0;
  }

  Future<int> _fetchPoints() async {
    // users/points answers a bare number; lidapoints/balance is the richer
    // rewards endpoint — use whichever succeeds first.
    for (final path in const [
      ApiEndpoints.lidapointsBalance,
      ApiEndpoints.points,
    ]) {
      try {
        return _asPoints(await _api.getRaw(path));
      } on ApiException catch (e) {
        if (e.statusCode == 401) rethrow;
        continue;
      }
    }
    return 0;
  }

  @override
  Future<List<Transaction>> getRecentTransactions({int limit = 5}) async {
    // No usable user id yet (e.g. OTP session while /users/profile is down):
    // return empty — the provider rebuilds with the id once auth state lands.
    // Throwing here bubbles into the dashboard build and blanks the screen.
    if (!_hasUserId) return const [];
    // Merged feed: ledger + Lida Value history + shop orders + points, so
    // Recent activity reflects everything, not just one endpoint.
    final feed = await ActivityFeed(
      _api,
      _userId!,
    ).fetch(ledgerLimit: limit < 25 ? 25 : limit);
    return feed.take(limit).toList();
  }

  @override
  Future<List<FlashDeal>> getFlashDeals() async {
    // No live deals endpoint yet; shop/products/featured is the intended
    // source once the backend exposes deal metadata (endsAt, discount).
    // Countdowns stay clock-relative until the server supplies endsAt.
    final now = DateTime.now();
    return [
      FlashDeal(
        id: 'd1',
        partnerName: 'Melcom Ghana',
        title: 'Samsung Galaxy A05 — 128GB',
        imageUrl: 'https://picsum.photos/seed/lida-a05/600/400',
        originalPrice: 850,
        dealPrice: 790,
        currency: 'GHS',
        endsAt: now.add(const Duration(hours: 2, minutes: 14, seconds: 9)),
        productId: 'prod_a05',
      ),
      FlashDeal(
        id: 'd2',
        partnerName: 'Melcom Ghana',
        title: 'Oraimo FreePods 4',
        imageUrl: 'https://picsum.photos/seed/lida-pods/600/400',
        originalPrice: 320,
        dealPrice: 259,
        currency: 'GHS',
        endsAt: now.add(const Duration(hours: 19, minutes: 45)),
        productId: 'prod_pods4',
      ),
      FlashDeal(
        id: 'd3',
        partnerName: 'Lidapay Shop',
        title: '10GB Telecel bundle voucher',
        imageUrl: 'https://picsum.photos/seed/lida-data/600/400',
        originalPrice: 60,
        dealPrice: 49,
        currency: 'GHS',
        endsAt: now.add(const Duration(minutes: 40)),
        productId: 'prod_10gb',
      ),
    ];
  }

  static double _asDouble(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0;
    return 0;
  }

  /// users/points returns a bare number; lidapoints/balance returns an object.
  static int _asPoints(Object? raw) {
    if (raw is num) return raw.round();
    if (raw is Map<String, dynamic>) {
      return _asDouble(raw['balance'] ?? raw['points']).round();
    }
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }
}
