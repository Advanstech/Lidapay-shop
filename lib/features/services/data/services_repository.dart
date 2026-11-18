import 'service_models.dart';

abstract class ServicesRepository {
  Future<List<ServiceOption>> getGhanaNetworks();
  Future<List<ServiceOption>> getCountries();

  /// POST /api/v1/reloadly/find-country-by-code — the country list does
  /// not include `callingCodes`, so a selected country's dial code is
  /// resolved lazily through this endpoint.
  Future<ServiceOption?> findCountryByCode(String isoCode);
  Future<List<ServiceOption>> getInternationalOperators(String countryCode);
  Future<List<ServiceOption>> getInternationalDataOperators(String countryCode);
  Future<List<DataBundle>> getDataBundles({required String networkId});

  /// POST /api/v1/reloadly/operator/autodetect — resolves the Reloadly
  /// airtime operator for [phone] in [countryIsoCode]. Returns the operator
  /// with suggested amounts, min/max and fx data for the amount step.
  Future<DetectedOperator> detectAirtimeOperator({
    required String phone,
    required String countryIsoCode,
    String? recipientDialCode,
  });

  /// GET /api/v1/reloadly-data/auto-detect — the data-bundle equivalent.
  Future<DetectedOperator> detectDataOperator({
    required String phone,
    required String countryIsoCode,
    String? recipientDialCode,
  });
  Future<ServiceReceipt> buyLocalAirtime({
    required String recipientNumber,
    required double amount,
    required String networkId,
    required bool saveToLidaValue,
    required String clientReference,
    bool isSelfTopup = false,
  });
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
  });
  Future<ServiceReceipt> buyDataBundle({
    required String recipientNumber,
    required String networkId,
    required DataBundle bundle,
    required bool saveToLidaValue,
    required String clientReference,
    bool isSelfTopup = false,
  });
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
  });
  Future<ServiceReceipt> payQr({
    required String merchantCode,
    required double amount,
  });
  Future<LidaValueWallet> getLidaValueWallet();

  /// GET /api/v1/lida-value/eligibility
  Future<bool> checkLidaValueEligibility();

  /// POST /lida-value/use — debit the sender's Lida Value for their own
  /// airtime/data top-up. [destination] is the user's own Ghana number;
  /// [serviceType] is `AIRTIME` or `DATA`.
  Future<ServiceReceipt> useLidaValue({
    required double amount,
    required String destination,
    String serviceType = 'AIRTIME',

    /// Prymo network code for the delivery the debit purchases — sent in
    /// `metadata.network` per the Lida Value contract.
    int? network,

    /// Ghana bundle code for DATA (the bundle list `id`), sent as
    /// `metadata.dataCode`. Ignored for AIRTIME.
    String? dataCode,
  });

  /// POST /lida-value/send — debit Lida Value to send airtime/data to
  /// [destination] (registered recipients get the delivery choice). For a
  /// pure value transfer the backend resolves the identifier itself.
  Future<ServiceReceipt> sendLidaValue({
    required double amount,
    required String destination,
    String serviceType = 'AIRTIME',
    String? note,
  });
  Future<ServiceReceipt> sellLidaValue({
    required double amount,
    String? destination,
  });

  /// [destination] follows the spec format `type:address`, e.g.
  /// `momo:0241234567`, `btc:1A2b3C…`, `bank:1234567890`.
  Future<ServiceReceipt> convertLidaValue({
    required double amount,
    String? destination,
  });
  Future<LidaPointsWallet> getLidaPointsWallet();
  Future<LidaPointsHistoryPage> getLidaPointsHistory({
    int page = 1,
    int limit = 20,
  });
  Future<ServiceReceipt> redeemPoints({required int points});

  /// Lidapoints redeem flow: options → quote → confirm (idempotent).
  Future<List<PointsRedeemOption>> getPointsRedeemOptions();
  Future<PointsRedeemQuote> getPointsRedeemQuote({
    required double points,
    required String optionId,
  });
  Future<ServiceReceipt> confirmPointsRedeem({
    required String quoteId,
    String? destination,
    required String idempotencyKey,
  });
  Future<AffiliateSummary> getAffiliateSummary();

  /// Invite & Earn overview: the shareable invitation link plus usage and
  /// points stats (GET /users/invitation-link/{generate,stats},
  /// GET /users/points).
  Future<InviteOverview> getInviteOverview();

  /// POST /api/v1/gtpay/services — bill-payment catalogue from the GTBank
  /// Partner API. [ServiceOption.id] is the ServiceName used by query/pay.
  Future<List<ServiceOption>> getGtPayServices();

  /// GET /api/v1/gtpay/banks — supported banks (needed for bank transfers).
  Future<List<ServiceOption>> getGtPayBanks();

  /// POST /api/v1/gtpay/pay — pays for a service after optional customer
  /// verification via query. Returns the GTBank transaction receipt.
  Future<ServiceReceipt> payGtPayService({
    required String serviceName,
    required String serviceNumber,
    String? secondaryServiceNumber,
    required double amount,
    required String remarks,
  });
}
