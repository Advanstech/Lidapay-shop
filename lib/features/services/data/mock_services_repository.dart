import 'dart:math';

import 'service_models.dart';
import 'services_repository.dart';

class MockServicesRepository implements ServicesRepository {
  static const _latency = Duration(milliseconds: 650);
  final _random = Random(7);

  @override
  Future<List<ServiceOption>> getGhanaNetworks() async {
    await Future<void>.delayed(_latency);
    return const [
      ServiceOption(id: '4', name: 'MTN Ghana', meta: 'Prymo network code 4'),
      ServiceOption(
        id: '6',
        name: 'Telecel Ghana',
        meta: 'Prymo network code 6',
      ),
      ServiceOption(id: '1', name: 'AirtelTigo', meta: 'Prymo network code 1'),
      ServiceOption(id: '3', name: 'Glo Ghana', meta: 'Prymo network code 3'),
      ServiceOption(id: '8', name: 'Busy', meta: 'Prymo network code 8'),
    ];
  }

  @override
  Future<List<ServiceOption>> getCountries() async {
    await Future<void>.delayed(_latency);
    return const [
      ServiceOption(id: 'GH', name: 'Ghana', meta: 'Reloadly sender country'),
      ServiceOption(
        id: 'NG',
        name: 'Nigeria',
        meta: 'MTN, Airtel, Glo, 9mobile',
      ),
      ServiceOption(id: 'KE', name: 'Kenya', meta: 'Safaricom, Airtel'),
      ServiceOption(id: 'US', name: 'United States', meta: 'Global operators'),
      ServiceOption(id: 'GB', name: 'United Kingdom', meta: 'Global operators'),
      // Stands in for a country the static picker lists never had: only the
      // live `reloadly/country-list` mentions it, and that payload ships no
      // calling code, so the wizard must resolve it by ISO code.
      ServiceOption(id: 'TG', name: 'Togo', meta: 'XOF'),
    ];
  }

  @override
  Future<ServiceOption?> findCountryByCode(String isoCode) async {
    await Future<void>.delayed(_latency);
    return switch (isoCode.toUpperCase()) {
      'GH' => const ServiceOption(
        id: 'GH',
        name: 'Ghana',
        dialCode: '+233',
        meta: 'GHS',
      ),
      'NG' => const ServiceOption(
        id: 'NG',
        name: 'Nigeria',
        dialCode: '+234',
        meta: 'NGN',
      ),
      'TG' => const ServiceOption(
        id: 'TG',
        name: 'Togo',
        dialCode: '+228',
        meta: 'XOF',
      ),
      _ => null,
    };
  }

  @override
  Future<List<ServiceOption>> getInternationalOperators(
    String countryCode,
  ) async {
    await Future<void>.delayed(_latency);
    return switch (countryCode.toUpperCase()) {
      'NG' => const [
        ServiceOption(id: '341', name: 'MTN Nigeria', meta: 'Reloadly'),
        ServiceOption(id: '342', name: 'Airtel Nigeria', meta: 'Reloadly'),
        ServiceOption(id: '344', name: 'Glo Nigeria', meta: 'Reloadly'),
      ],
      'KE' => const [
        ServiceOption(id: '265', name: 'Safaricom', meta: 'Reloadly'),
        ServiceOption(id: '268', name: 'Airtel Kenya', meta: 'Reloadly'),
      ],
      _ => const [
        ServiceOption(
          id: '900',
          name: 'Auto-detect operator',
          meta: 'Reloadly',
        ),
      ],
    };
  }

  @override
  Future<List<ServiceOption>> getInternationalDataOperators(
    String countryCode,
  ) async {
    await Future<void>.delayed(_latency);
    return switch (countryCode.toUpperCase()) {
      'NG' => const [
        ServiceOption(id: '341', name: 'MTN Nigeria', meta: 'Reloadly data'),
        ServiceOption(id: '344', name: 'Glo Nigeria', meta: 'Reloadly data'),
      ],
      'KE' => const [
        ServiceOption(id: '265', name: 'Safaricom', meta: 'Reloadly data'),
      ],
      _ => const [
        ServiceOption(
          id: '900',
          name: 'Auto-detect operator',
          meta: 'Reloadly data',
        ),
      ],
    };
  }

  @override
  Future<List<DataBundle>> getDataBundles({required String networkId}) async {
    await Future<void>.delayed(_latency);
    return const [
      DataBundle(
        id: 'DATA_1GB',
        name: 'Starter Bundle',
        price: 12,
        dataAmount: '1GB',
      ),
      DataBundle(
        id: 'DATA_5GB',
        name: 'Everyday Bundle',
        price: 48,
        dataAmount: '5GB',
      ),
      DataBundle(
        id: 'DATA_10GB',
        name: 'Power Bundle',
        price: 88,
        dataAmount: '10GB',
      ),
      DataBundle(
        id: 'DATA_25GB',
        name: 'Family Bundle',
        price: 185,
        dataAmount: '25GB',
      ),
    ];
  }

  @override
  Future<DetectedOperator> detectAirtimeOperator({
    required String phone,
    required String countryIsoCode,
    String? recipientDialCode,
  }) async {
    if (countryIsoCode.toUpperCase() == 'GH') {
      // Reloadly's MTN Ghana operatorId — maps to Prymo network code 4.
      return const DetectedOperator(
        id: 150,
        name: 'MTN Ghana',
        minAmount: 1,
        maxAmount: 45,
        suggestedAmounts: [1, 5, 10, 20, 50],
        senderCurrencyCode: 'GHS',
        senderCurrencySymbol: 'GH₵',
        destinationCurrencyCode: 'GHS',
      );
    }
    return const DetectedOperator(
      id: 341,
      name: 'MTN Nigeria',
      minAmount: 1,
      maxAmount: 100,
      suggestedAmounts: [5, 10, 20, 50, 100],
      senderCurrencyCode: 'USD',
      senderCurrencySymbol: '\$',
      destinationCurrencyCode: 'NGN',
      fxRate: 4.2,
      fxCurrencyCode: 'GHS',
    );
  }

  @override
  Future<DetectedOperator> detectDataOperator({
    required String phone,
    required String countryIsoCode,
    String? recipientDialCode,
  }) async {
    return const DetectedOperator(
      id: 341,
      name: 'MTN Nigeria',
      minAmount: 1,
      maxAmount: 100,
      suggestedAmounts: [5, 10, 20, 50],
      senderCurrencyCode: 'USD',
      senderCurrencySymbol: '\$',
      destinationCurrencyCode: 'NGN',
    );
  }

  @override
  Future<ServiceReceipt> buyLocalAirtime({
    required String recipientNumber,
    required double amount,
    required String networkId,
    required bool saveToLidaValue,
    required String clientReference,
    bool isSelfTopup = false,
  }) async {
    await Future<void>.delayed(_latency);
    return _receipt(
      prefix: 'AIR',
      title: saveToLidaValue ? 'Airtime saved to Lida Value' : 'Airtime credited',
      message: 'Airtime credited to $recipientNumber.',
      amount: amount,
      recipientNumber: recipientNumber,
      networkName: networkId,
      currency: 'GHS',
      serviceType: 'AIRTIME',
    );
  }

  @override
  Future<ServiceReceipt> buyGlobalAirtime({
    required String recipientNumber,
    required double amount,
    required String countryCode,
    String? operatorId,
    String? recipientDialCode,
    String? recipientEmail,
    String? senderNumber,
    String senderCountryCode = 'GH',
    String currency = 'USD',
    required String clientReference,
    bool isSelfTopup = false,
  }) async {
    await Future<void>.delayed(_latency);
    return _receipt(
      prefix: 'RLD',
      title: 'Global airtime credited',
      message: 'Airtime credited to $recipientNumber in $countryCode.',
      amount: amount,
      recipientNumber: recipientNumber,
      networkName: operatorId,
      currency: currency,
      serviceType: 'AIRTIME',
    );
  }

  @override
  Future<ServiceReceipt> buyDataBundle({
    required String recipientNumber,
    required String networkId,
    required DataBundle bundle,
    required bool saveToLidaValue,
    required String clientReference,
    bool isSelfTopup = false,
  }) async {
    await Future<void>.delayed(_latency);
    final bundleLabel = '${bundle.dataAmount} ${bundle.name}'.trim();
    return _receipt(
      prefix: 'DAT',
      title: saveToLidaValue ? 'Data value saved' : 'Data bundle credited',
      message: '$bundleLabel credited to $recipientNumber.',
      amount: bundle.price,
      recipientNumber: recipientNumber,
      networkName: networkId,
      bundleName: bundleLabel,
      currency: 'GHS',
      serviceType: 'DATA',
    );
  }

  @override
  Future<ServiceReceipt> buyGlobalDataBundle({
    required String recipientNumber,
    required double amount,
    required String countryCode,
    String? operatorId,
    String? operatorName,
    String? recipientDialCode,
    String? recipientEmail,
    String? senderNumber,
    String senderCountryCode = 'GH',
    String currency = 'USD',
    required String clientReference,
    bool isSelfTopup = false,
  }) async {
    await Future<void>.delayed(_latency);
    return _receipt(
      prefix: 'DAT',
      title: 'Data bundle credited',
      message: 'Data bundle credited to $recipientNumber in $countryCode.',
      amount: amount,
      recipientNumber: recipientNumber,
      networkName: operatorName ?? operatorId,
      currency: currency,
      serviceType: 'DATA',
    );
  }

  @override
  Future<ServiceReceipt> payQr({
    required String merchantCode,
    required double amount,
  }) async {
    await Future<void>.delayed(_latency);
    return _receipt(
      prefix: 'QRP',
      title: 'QR payment complete',
      message: 'Merchant $merchantCode has received your wallet payment.',
      amount: amount,
    );
  }

  @override
  Future<LidaValueWallet> getLidaValueWallet() async {
    await Future<void>.delayed(_latency);
    return LidaValueWallet(
      balance: 324.50,
      pending: 78.00,
      history: [
        _staticReceipt(
          'LV-77812',
          'Accepted value',
          'Saved from recipient choice',
          25,
        ),
        _staticReceipt(
          'LV-77501',
          'Converted value',
          'Converted to wallet balance',
          42,
        ),
        _staticReceipt(
          'LV-77102',
          'Sold value',
          'Sold back to Lidapay wallet',
          18,
        ),
      ],
    );
  }

  @override
  Future<bool> checkLidaValueEligibility() async => true;

  @override
  Future<ServiceReceipt> useLidaValue({
    required double amount,
    required String destination,
    String serviceType = 'AIRTIME',
    String? clientReference,
    int? network,
    String? dataCode,
  }) async {
    await Future<void>.delayed(_latency);
    return _receipt(
      prefix: 'LVU',
      title: 'Lida Value used',
      message: '$serviceType for $destination charged to Lida Value.',
      amount: amount,
    );
  }

  @override
  Future<ServiceReceipt> sendLidaValue({
    required double amount,
    required String destination,
    String serviceType = 'AIRTIME',
    String? note,
    String? clientReference,
  }) async {
    await Future<void>.delayed(_latency);
    return _receipt(
      prefix: 'LVSND',
      title: 'USE_SEND',
      message:
          'Sent to $destination${note != null && note.isNotEmpty ? ' · $note' : ''}',
      amount: amount,
    );
  }

  @override
  Future<ServiceReceipt> sellLidaValue({
    required double amount,
    String? destination,
  }) async {
    await Future<void>.delayed(_latency);
    return _receipt(
      prefix: 'LVS',
      title: 'Lida Value sold',
      message: 'Funds moved to your wallet.',
      amount: amount,
    );
  }

  @override
  Future<ServiceReceipt> convertLidaValue({
    required double amount,
    String? destination,
  }) async {
    await Future<void>.delayed(_latency);
    return _receipt(
      prefix: 'LVC',
      title: 'Lida Value converted',
      message: 'Value converted to Lida Points.',
      amount: amount,
    );
  }

  @override
  Future<LidaPointsWallet> getLidaPointsWallet() async {
    await Future<void>.delayed(_latency);
    return LidaPointsWallet(
      balance: 18450,
      redeemableValue: 92.25,
      history: [
        _staticReceipt(
          'LP-5101',
          'Shop reward',
          'Earned from order ORD-22115',
          210,
        ),
        _staticReceipt(
          'LP-5090',
          'Airtime reward',
          'Earned from MTN top-up',
          45,
        ),
        _staticReceipt(
          'LP-5077',
          'Referral bonus',
          'Ama joined with your code',
          500,
        ),
      ],
    );
  }

  @override
  Future<LidaPointsHistoryPage> getLidaPointsHistory({
    int page = 1,
    int limit = 20,
  }) async {
    final wallet = await getLidaPointsWallet();
    final items = page == 1 ? wallet.history : const <ServiceReceipt>[];
    return LidaPointsHistoryPage(
      items: items,
      page: page,
      limit: limit,
      hasMore: false,
      total: wallet.history.length,
      totalPages: 1,
    );
  }

  @override
  Future<List<PointsRedeemOption>> getPointsRedeemOptions() async => const [
    PointsRedeemOption(
      id: 'airtime',
      name: 'Airtime top-up',
      description: 'Credit any phone with airtime',
      minPoints: 500,
      needsDestination: true,
    ),
    PointsRedeemOption(
      id: 'data',
      name: 'Data bundle',
      description: 'Data bundle for any number',
      minPoints: 500,
      needsDestination: true,
    ),
    PointsRedeemOption(
      id: 'cash_momo',
      name: 'Cash to MoMo',
      description: 'Cash value to a mobile money wallet',
      minPoints: 1000,
      needsDestination: true,
    ),
    PointsRedeemOption(
      id: 'lida_value',
      name: 'Lida Value credit',
      description: 'Convert points into Lida Value',
      minPoints: 200,
    ),
  ];

  @override
  Future<PointsRedeemQuote> getPointsRedeemQuote({
    required double points,
    String? optionId,
  }) async {
    await Future<void>.delayed(_latency);
    return PointsRedeemQuote(
      quoteId: 'LPRQ-${DateTime.now().millisecondsSinceEpoch}',
      points: points,
      cashValue: points / 200,
      currency: 'GHS',
    );
  }

  @override
  Future<ServiceReceipt> confirmPointsRedeem({
    required String quoteId,
    String? destination,
    required String idempotencyKey,
  }) async {
    await Future<void>.delayed(_latency);
    return _receipt(
      prefix: 'LPR',
      title: 'Points redeemed',
      message: 'Quote $quoteId settled.',
      amount: 5,
    );
  }

  @override
  Future<ServiceReceipt> redeemPoints({required int points}) async {
    await Future<void>.delayed(_latency);
    return _receipt(
      prefix: 'LPR',
      title: 'Points redeemed',
      message: '$points points converted to wallet value.',
      amount: points / 200,
    );
  }

  @override
  Future<AffiliateSummary> getAffiliateSummary() async {
    await Future<void>.delayed(_latency);
    return const AffiliateSummary(
      code: 'LIDA-AMA-24',
      totalInvites: 18,
      activeUsers: 11,
      earnings: 146.75,
    );
  }

  @override
  Future<InviteOverview> getInviteOverview() async {
    await Future<void>.delayed(_latency);
    return InviteOverview(
      link: 'https://lidapay.app/invite/demo/PAA-GRANT-24',
      totalUsageCount: 3,
      totalPointsEarned: 60,
      userPoints: 160,
      links: const [
        InvitationLink(
          link: 'https://lidapay.app/invite/demo/PAA-GRANT-24',
          usageCount: 3,
          pointsEarned: 60,
        ),
      ],
    );
  }

  @override
  Future<List<ServiceOption>> getGtPayServices() async {
    await Future<void>.delayed(_latency);
    return const [
      ServiceOption(
        id: 'airtime',
        name: 'Airtime Top-up',
        meta: 'Buy airtime for any network',
      ),
      ServiceOption(
        id: 'creditwallet',
        name: 'Wallet Top-up',
        meta: 'Fund a Lidapay wallet',
      ),
      ServiceOption(
        id: 'banktrf',
        name: 'Bank Transfer',
        meta: 'Send to any Ghanaian bank',
      ),
    ];
  }

  @override
  Future<List<ServiceOption>> getGtPayBanks() async {
    await Future<void>.delayed(_latency);
    return const [
      ServiceOption(id: '901', name: 'Access Bank', meta: 'GIP bank code'),
      ServiceOption(id: '902', name: 'Ecobank Ghana', meta: 'GIP bank code'),
      ServiceOption(id: '903', name: 'Fidelity Bank', meta: 'GIP bank code'),
      ServiceOption(id: '904', name: 'GCB Bank', meta: 'GIP bank code'),
    ];
  }

  @override
  Future<ServiceReceipt> payGtPayService({
    required String serviceName,
    required String serviceNumber,
    String? secondaryServiceNumber,
    required double amount,
    required String remarks,
  }) async {
    await Future<void>.delayed(_latency);
    return _receipt(
      prefix: 'GTP',
      title: 'GTPay transaction complete',
      message: '$serviceName payment of $serviceNumber completed. $remarks',
      amount: amount,
    );
  }

  ServiceReceipt _receipt({
    required String prefix,
    required String title,
    required String message,
    required double amount,
    String? recipientNumber,
    String? networkName,
    String? bundleName,
    String? currency,
    String? serviceType,
  }) {
    final serial = 100000 + _random.nextInt(899999);
    return ServiceReceipt(
      reference: '$prefix-$serial',
      title: title,
      message: message,
      amount: amount,
      createdAt: DateTime.now(),
      recipientNumber: recipientNumber,
      networkName: networkName,
      bundleName: bundleName,
      currency: currency,
      serviceType: serviceType,
    );
  }

  ServiceReceipt _staticReceipt(
    String reference,
    String title,
    String message,
    double amount,
  ) {
    return ServiceReceipt(
      reference: reference,
      title: title,
      message: message,
      amount: amount,
      createdAt: DateTime.now().subtract(
        Duration(days: _random.nextInt(12) + 1),
      ),
    );
  }
}
