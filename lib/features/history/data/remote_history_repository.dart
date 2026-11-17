import 'dart:async';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_payload.dart';
import '../../dashboard/data/activity_feed.dart';
import '../../dashboard/data/dashboard_models.dart';
import 'history_models.dart';
import 'history_repository.dart';

/// Live activity ledger over the merged [ActivityFeed] (transactions,
/// Lida Value history, shop orders, points). The ledger endpoints expose
/// no filter parameters beyond date range, so filters and pagination
/// apply client-side over the merged feed.
class RemoteHistoryRepository implements HistoryRepository {
  RemoteHistoryRepository(this._api, this._userId);

  final ApiClient _api;
  final String? _userId;

  String get _requiredUserId {
    final id = _userId;
    if (id == null || id.isEmpty) {
      throw const ApiException(
        'We\'re finishing your sign-in. Please try again in a moment.',
        statusCode: 401,
      );
    }
    return id;
  }

  @override
  Future<List<Transaction>> getTransactions({
    int page = 1,
    int pageSize = 10,
    HistoryFilter? filter,
  }) async {
    // One extra row beyond the page acts as the has-more signal, so an
    // exactly-full final page no longer reads as "more to fetch".
    final needed = page * pageSize + 1;
    var ledgerLimit = page * pageSize + 50;
    var feed = await ActivityFeed(
      _api,
      _userId ?? '',
    ).fetch(ledgerLimit: ledgerLimit);
    var items = feed;
    if (filter != null && filter.isActive) {
      items = items.where(filter.matches).toList();
    }
    // Sparse matches under a filter can sit beyond the fetched window;
    // grow the ledger (bounded) until page+sentinel fills or the merged
    // feed stops growing.
    while (items.length < needed &&
        feed.length >= ledgerLimit &&
        ledgerLimit < 500) {
      ledgerLimit += 100;
      final next = await ActivityFeed(
        _api,
        _userId ?? '',
      ).fetch(ledgerLimit: ledgerLimit);
      if (next.length <= feed.length) break;
      feed = next;
      items = feed;
      if (filter != null && filter.isActive) {
        items = items.where(filter.matches).toList();
      }
    }
    final start = (page - 1) * pageSize;
    if (start >= items.length) return const [];
    final end = start + pageSize + 1;
    return items.sublist(start, end > items.length ? items.length : end);
  }

  @override
  Future<List<TransactionStat>> getStats() async {
    final raw = await _api.getRaw(
      ApiEndpoints.transactionsStats(_requiredUserId),
    );
    return rowsOf(raw)
        .map((row) => TransactionStat.fromJson(row))
        .where((s) => s.count > 0)
        .toList();
  }

  @override
  Future<List<Transaction>> getByDateRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final raw = await _api.getRaw(
      ApiEndpoints.transactionsDateRange,
      queryParameters: {
        'startDate': start.toIso8601String(),
        'endDate': end.toIso8601String(),
      },
    );
    return rowsOf(raw).map((row) => Transaction.fromApiJson(row)).toList();
  }
}
