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
      : (user.fullName.isEmpty ? user.phoneNumber : user.fullName);
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
final affiliateSummaryProvider = FutureProvider<AffiliateSummary>(
  (ref) => ref.watch(servicesRepositoryProvider).getAffiliateSummary(),
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
