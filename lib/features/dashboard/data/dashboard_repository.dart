import 'dashboard_models.dart';

abstract class DashboardRepository {
  Future<WalletSummary> getWalletSummary();

  /// Last [limit] transactions for the dashboard feed.
  Future<List<Transaction>> getRecentTransactions({int limit = 5});

  /// Active partner deals; [endsAt] values come from the server.
  Future<List<FlashDeal>> getFlashDeals();
}
