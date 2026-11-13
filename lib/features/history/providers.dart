import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../dashboard/data/dashboard_models.dart';
import 'data/history_models.dart';
import 'data/history_repository.dart';
import 'data/remote_history_repository.dart';

/// One-line swap point between the mock backend and the live API.
final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  final userId = ref.watch(authSessionProvider)?.user.id;
  return RemoteHistoryRepository(ref.watch(apiClientProvider), userId);
});

class HistoryState extends Equatable {
  const HistoryState({
    required this.items,
    required this.hasMore,
    required this.filter,
  });

  final List<Transaction> items;
  final bool hasMore;

  /// Active advanced filter; [HistoryFilter.isActive] false = unfiltered.
  final HistoryFilter filter;

  HistoryState copyWith({
    List<Transaction>? items,
    bool? hasMore,
    HistoryFilter? filter,
  }) {
    return HistoryState(
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      filter: filter ?? this.filter,
    );
  }

  @override
  List<Object?> get props => [items, hasMore, filter];
}

final historyProvider =
    StateNotifierProvider<HistoryController, AsyncValue<HistoryState>>((ref) {
      return HistoryController(ref.watch(historyRepositoryProvider));
    });

class HistoryController extends StateNotifier<AsyncValue<HistoryState>> {
  HistoryController(this._repository) : super(const AsyncLoading()) {
    load();
  }

  static const _pageSize = 10;

  final HistoryRepository _repository;
  int _page = 0;
  bool _loadingMore = false;
  Timer? _settleTimer;
  int _settleAttempts = 0;
  static const _maxSettleAttempts = 10;

  Future<void> load() async {
    final filter = state.valueOrNull?.filter ?? const HistoryFilter();
    state = const AsyncLoading();
    final first = await AsyncValue.guard(
      () => _repository.getTransactions(
        page: 1,
        pageSize: _pageSize,
        filter: filter,
      ),
    );
    if (!mounted) return;
    state = first.whenData((items) {
      _page = 1;
      return HistoryState(
        items: items,
        hasMore: items.length == _pageSize,
        filter: filter,
      );
    });
    _scheduleSettleCheck();
  }

  /// Points and top-ups can land PENDING server-side; re-fetch the merged
  /// feed (which includes /lidapoints/history) until they settle, so a
  /// point is never left "pending" on screen after the backend resolves.
  void _scheduleSettleCheck() {
    _settleTimer?.cancel();
    final hasPending =
        state.valueOrNull?.items.any(
          (t) => t.status == TransactionStatus.pending,
        ) ??
        false;
    if (!hasPending || _settleAttempts >= _maxSettleAttempts) {
      _settleAttempts = 0;
      return;
    }
    _settleAttempts++;
    _settleTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) load();
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  Future<void> setFilter(HistoryFilter filter) async {
    state = AsyncData(
      HistoryState(items: const [], hasMore: false, filter: filter),
    );
    await load();
  }

  /// Convenience for the quick type chips — preserves any other active
  /// filter facets.
  Future<void> setTypeFilter(TransactionType? type) async {
    final current = state.valueOrNull?.filter ?? const HistoryFilter();
    await setFilter(current.copyWith(types: type == null ? const {} : {type}));
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || _loadingMore) return;
    _loadingMore = true;
    final next = await AsyncValue.guard(
      () => _repository.getTransactions(
        page: _page + 1,
        pageSize: _pageSize,
        filter: current.filter,
      ),
    );
    if (!mounted) return;
    next.whenData((items) {
      _page += 1;
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...items],
          hasMore: items.length == _pageSize,
        ),
      );
    });
    _loadingMore = false;
  }
}

/// Server-side aggregates grouped by {transType, status} — count, totals,
/// averages. Best-effort: an empty list when the endpoint is unavailable.
final transactionStatsProvider = FutureProvider<List<TransactionStat>>((
  ref,
) async {
  try {
    return await ref.watch(historyRepositoryProvider).getStats();
  } on ApiException {
    return const [];
  }
});

/// The analytics bundle: the merged feed (wider window than the paged
/// ledger) plus server stats, aggregated into chart-ready series and
/// generated insights.
final historyAnalyticsProvider = FutureProvider<HistoryAnalytics>((ref) async {
  final repo = ref.watch(historyRepositoryProvider);
  final transactions = await repo.getTransactions(page: 1, pageSize: 200);
  List<TransactionStat> stats;
  try {
    stats = await repo.getStats();
  } on ApiException {
    stats = const [];
  }
  return HistoryAnalytics.build(transactions, stats);
});
