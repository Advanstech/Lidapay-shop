import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import '../../core/network/api_client.dart';
import 'data/remote_services_repository.dart';
import 'data/service_models.dart';
import 'data/services_repository.dart';

/// One-line swap point between the mock backend and the live API. Watches the
/// session so GTPay payments are attributed to the signed-in user and every
/// provider below refreshes when the user changes.
final servicesRepositoryProvider = Provider<ServicesRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  final user = session?.user;
  final name = user == null
      ? null
      : (user.fullName.isNotEmpty
            ? user.fullName
            : user.phoneNumber.isNotEmpty
            ? user.phoneNumber
            : user.username.isNotEmpty
            ? user.username
            : (user.email.isNotEmpty ? user.email : null));
  return RemoteServicesRepository(
    ref.watch(apiClientProvider),
    userId: user?.id,
    userName: name,
    userPhone: user?.phoneNumber,
  );
});

final ghanaNetworksProvider = FutureProvider<List<ServiceOption>>(
  (ref) => ref.watch(servicesRepositoryProvider).getGhanaNetworks(),
);
final countriesProvider = FutureProvider<List<ServiceOption>>(
  (ref) => ref.watch(servicesRepositoryProvider).getCountries(),
);
final internationalOperatorsProvider =
    FutureProvider.family<List<ServiceOption>, String>(
      (ref, countryCode) => ref
          .watch(servicesRepositoryProvider)
          .getInternationalOperators(countryCode),
    );
final internationalDataOperatorsProvider =
    FutureProvider.family<List<ServiceOption>, String>(
      (ref, countryCode) => ref
          .watch(servicesRepositoryProvider)
          .getInternationalDataOperators(countryCode),
    );
final lidaValueProvider = FutureProvider<LidaValueWallet>(
  (ref) => ref.watch(servicesRepositoryProvider).getLidaValueWallet(),
);
final pointsRedeemOptionsProvider = FutureProvider<List<PointsRedeemOption>>(
  (ref) => ref.watch(servicesRepositoryProvider).getPointsRedeemOptions(),
);
final lidaPointsProvider = FutureProvider<LidaPointsWallet>(
  (ref) => ref.watch(servicesRepositoryProvider).getLidaPointsWallet(),
);

/// Paginated state for the Lida Points activity ledger (`GET /lidapoints/history`).
class LidaPointsHistoryState {
  const LidaPointsHistoryState({
    required this.items,
    required this.page,
    required this.hasMore,
    this.total,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<ServiceReceipt> items;
  final int page;
  final bool hasMore;
  final int? total;
  final bool loadingMore;
  final String? loadMoreError;

  LidaPointsHistoryState copyWith({
    List<ServiceReceipt>? items,
    int? page,
    bool? hasMore,
    int? total,
    bool? loadingMore,
    String? loadMoreError,
    bool clearLoadMoreError = false,
  }) => LidaPointsHistoryState(
    items: items ?? this.items,
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    total: total ?? this.total,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: clearLoadMoreError
        ? null
        : (loadMoreError ?? this.loadMoreError),
  );
}

final lidaPointsHistoryProvider = StateNotifierProvider.autoDispose<
  LidaPointsHistoryController,
  AsyncValue<LidaPointsHistoryState>
>((ref) {
  return LidaPointsHistoryController(ref.watch(servicesRepositoryProvider));
});

class LidaPointsHistoryController
    extends StateNotifier<AsyncValue<LidaPointsHistoryState>> {
  LidaPointsHistoryController(this._repo) : super(const AsyncLoading()) {
    refresh();
  }

  static const int _pageSize = 20;
  final ServicesRepository _repo;
  bool _loadingMore = false;

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final page = await _repo.getLidaPointsHistory(
        page: 1,
        limit: _pageSize,
      );
      return LidaPointsHistoryState(
        items: page.items,
        page: page.page,
        hasMore: page.hasMore,
        total: page.total,
      );
    });
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || _loadingMore) return;
    _loadingMore = true;
    state = AsyncData(
      current.copyWith(loadingMore: true, clearLoadMoreError: true),
    );
    try {
      final nextPageNumber = current.page + 1;
      final next = await _repo.getLidaPointsHistory(
        page: nextPageNumber,
        limit: _pageSize,
      );
      final seen = current.items.map((e) => e.reference).toSet();
      final appended = [
        ...current.items,
        for (final item in next.items)
          if (seen.add(item.reference)) item,
      ];
      state = AsyncData(
        LidaPointsHistoryState(
          items: appended,
          page: nextPageNumber,
          hasMore: next.hasMore && next.items.isNotEmpty,
          total: next.total ?? current.total,
        ),
      );
    } catch (e) {
      state = AsyncData(
        current.copyWith(
          loadingMore: false,
          loadMoreError: 'Could not load more points activity.',
        ),
      );
    } finally {
      _loadingMore = false;
    }
  }
}
final affiliateSummaryProvider = FutureProvider<AffiliateSummary>(
  (ref) => ref.watch(servicesRepositoryProvider).getAffiliateSummary(),
);
final inviteOverviewProvider = FutureProvider<InviteOverview>(
  (ref) => ref.watch(servicesRepositoryProvider).getInviteOverview(),
);
final gtPayServicesProvider = FutureProvider<List<ServiceOption>>(
  (ref) => ref.watch(servicesRepositoryProvider).getGtPayServices(),
);
final gtPayBanksProvider = FutureProvider<List<ServiceOption>>(
  (ref) => ref.watch(servicesRepositoryProvider).getGtPayBanks(),
);

final dataBundlesProvider = FutureProvider.family<List<DataBundle>, String>(
  (ref, networkId) => ref
      .watch(servicesRepositoryProvider)
      .getDataBundles(networkId: networkId),
);
