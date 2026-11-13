import '../../dashboard/data/dashboard_models.dart';
import 'history_models.dart';

abstract class HistoryRepository {
  /// GET /api/v1/transactions — paginated ledger. [filter] applies
  /// client-side over the merged feed so Lida Value, points and shop rows
  /// stay visible under every filter combination.
  Future<List<Transaction>> getTransactions({
    int page = 1,
    int pageSize = 10,
    HistoryFilter? filter,
  });

  /// GET /api/v1/transactions/stats/{userId} — server-side aggregates
  /// grouped by `{transType, status}` (count/total/avg/min/max).
  Future<List<TransactionStat>> getStats();

  /// GET /api/v1/transactions/date-range — raw ledger rows between two
  /// dates. Powers the analytics trend window.
  Future<List<Transaction>> getByDateRange({
    required DateTime start,
    required DateTime end,
  });
}
