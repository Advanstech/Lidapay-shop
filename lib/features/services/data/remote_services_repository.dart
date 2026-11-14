import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_payload.dart';
import '../../../core/utils/formatters.dart';
import 'service_models.dart';
import 'services_repository.dart';

/// Live services data. Most of these endpoints document a request body but no
/// response example, so every read goes through the tolerant helpers below
/// (multi-key lookups, envelope unwrapping) rather than a fixed model.
class RemoteServicesRepository implements ServicesRepository {
  RemoteServicesRepository(
    this._api, {
    String? userId,
    String? userName,
    String? userPhone,
  }) : _userId = userId,
       _userName = userName,
       _userPhone = userPhone;

  final ApiClient _api;
  final String? _userId;
  final String? _userName;
  final String? _userPhone;

  /// The OTP verify response can carry JS-serialized `undefined`/`null`
  /// literals for identity fields — those poison endpoints that require a
  /// real user id. Treat them as absent rather than sending them.
  static String? _usable(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty || v == 'undefined' || v == 'null') {
      return null;
    }
    return v;
  }

  String? get _effectiveUserId => _usable(_userId);
  String? get _effectiveUserName => _usable(_userName) ?? _usable(_userPhone);

  /// Catalogue data (countries, operators, bundles) changes rarely, so every
  /// successful payload is persisted and the stale copy is served when the
  /// live call fails — a provider outage can't dead-end the wizard once the
  /// catalogue has been fetched at least once.
  static const _cataloguePrefix = 'svc_catalogue_v1:';

  Future<dynamic> _catalogue(
    String key,
    Future<dynamic> Function() fetch,
  ) async {
    try {
      final raw = await fetch();
      if (raw != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('$_cataloguePrefix$key', jsonEncode(raw));
      }
      return raw;
    } on ApiException {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('$_cataloguePrefix$key');
      if (cached != null && cached.isNotEmpty) return jsonDecode(cached);
      rethrow;
    }
  }

  /// MoMo transfer, AdvansisPay, QR Pay and points redemption must not
  /// report success until their live transaction lifecycles are integrated.
  Future<ServiceReceipt> _unavailable(String service) => Future.error(
    ApiException(
      '$service is not available yet. No transaction was submitted.',
    ),
  );

  static const _senderCountry = 'GH';

  @override
  Future<List<ServiceOption>> getGhanaNetworks() async {
    // Prymo One4All codes are fixed by the contract, not catalog data.
    return const [
      ServiceOption(id: '4', name: 'MTN Ghana', meta: 'Prymo network code 4'),
      ServiceOption(id: '1', name: 'AirtelTigo', meta: 'Prymo network code 1'),
      ServiceOption(
        id: '6',
        name: 'Telecel Ghana',
        meta: 'Prymo network code 6',
      ),
      ServiceOption(id: '3', name: 'Glo Ghana', meta: 'Prymo network code 3'),
      ServiceOption(id: '8', name: 'Busy', meta: 'Prymo network code 8'),
      ServiceOption(id: '9', name: 'Surfline', meta: 'Prymo network code 9'),
    ];
  }

  @override
  Future<List<ServiceOption>> getCountries() async {
    try {
      final rows = rowsOf(
        await _catalogue(
          'countries',
          () => _api.getRaw(ApiEndpoints.reloadlyCountryList),
        ),
      );
      final countries = rows
          .map((row) {
            final pool = payloadPool(row);
            final code = stringField(pool, const [
              'isoName',
              'code',
              'iso2',
              'countryIsoCode',
              'id',
            ]);
            final name = stringField(pool, const [
              'name',
              'countryName',
              'shortName',
              'displayName',
            ]);
            if (code == null || name == null) return null;
            final rawDialCode =
                pool['callingCode'] ??
                pool['dialCode'] ??
                pool['phoneCode'] ??
                pool['callingCodes'];
            var dialCode = rawDialCode is List
                ? (rawDialCode.isEmpty ? null : rawDialCode.first.toString())
                : rawDialCode?.toString();
            if (dialCode != null &&
                dialCode.isNotEmpty &&
                !dialCode.startsWith('+')) {
              dialCode = '+$dialCode';
            }
            return ServiceOption(
              id: code,
              name: name,
              meta: stringField(pool, const [
                'currencyCode',
                'currencyIsoCode',
              ]),
              dialCode: dialCode,
              flagUrl: stringField(pool, const [
                'flagUrl',
                'flag',
                'flagImage',
                'flagIcon',
              ]),
            );
          })
          .whereType<ServiceOption>()
          .toList();
      if (countries.isEmpty) return _staticCountries();
      return _sorted(countries);
    } on ApiException {
      return _staticCountries();
    }
  }

  @override
  Future<ServiceOption?> findCountryByCode(String isoCode) async {
    final iso = isoCode.trim().toUpperCase();
    if (iso.isEmpty) return null;
    try {
      final raw = await _api.postRaw(
        ApiEndpoints.reloadlyFindCountryByCode,
        body: {'countryCode': iso},
      );
      final pool = payloadPool(asMap(raw));
      final rawDialCode =
          pool['callingCode'] ??
          pool['dialCode'] ??
          pool['phoneCode'] ??
          pool['callingCodes'];
      var dialCode = rawDialCode is List
          ? (rawDialCode.isEmpty ? null : rawDialCode.first.toString())
          : rawDialCode?.toString();
      if (dialCode != null &&
          dialCode.isNotEmpty &&
          !dialCode.startsWith('+')) {
        dialCode = '+$dialCode';
      }
      return ServiceOption(
        id: stringField(pool, const ['isoName', 'code', 'iso2']) ?? iso,
        name: stringField(pool, const ['name', 'countryName']) ?? iso,
        meta: stringField(pool, const ['currencyCode', 'currencyIsoCode']),
        dialCode: dialCode,
        flagUrl: stringField(pool, const ['flagUrl', 'flag']),
      );
    } on ApiException {
      return null;
    }
  }

  /// Ghana is the domestic (Prymo) route — keep it pinned on top so users
  /// can flip between local and Reloadly destinations without searching.
  static List<ServiceOption> _sorted(List<ServiceOption> countries) {
    countries.sort((a, b) {
      if (a.id == 'GH') return -1;
      if (b.id == 'GH') return 1;
      return a.name.compareTo(b.name);
    });
    return countries;
  }

  @override
  Future<List<ServiceOption>> getInternationalOperators(
    String countryCode,
  ) async {
    final iso = countryCode.trim().toUpperCase();
    if (iso.isEmpty || iso == _senderCountry) {
      // Ghana destinations ride the domestic Prymo route instead.
      return getGhanaNetworks();
    }
    final raw = await _catalogue(
      'operators:$iso',
      () => _operatorCatalogue(iso: iso),
    );
    return _parseOperators(raw, countryIso: iso);
  }

  @override
  Future<List<ServiceOption>> getInternationalDataOperators(
    String countryCode,
  ) async {
    final iso = countryCode.trim().toUpperCase();
    if (iso.isEmpty || iso == _senderCountry) {
      return getGhanaNetworks();
    }
    final raw = await _catalogue(
      'data-operators:$iso',
      () => _operatorCatalogue(iso: iso, dataOnly: true),
    );
    return _parseOperators(raw, countryIso: iso, dataOnly: true);
  }

  /// Operator discovery for a destination, in the order the handoff contract
  /// documents it: the data-eligible list for data, `network-operators` with
  /// `countryIsoCode` for airtime. The backend mints its Reloadly token per
  /// route, so one route failing says nothing about the others — walk the
  /// remaining routes before reporting the destination unavailable.
  Future<Object?> _operatorCatalogue({
    required String iso,
    bool dataOnly = false,
  }) async {
    Future<Object?> networkOperators() => _api.postRaw(
      ApiEndpoints.reloadlyNetworkOperators,
      body: {
        'countryIsoCode': iso,
        'size': 100,
        'page': 0,
        'includeBundles': true,
        'includeData': true,
      },
    );

    Future<Object?> dataOperators() => _api.postRaw(
      ApiEndpoints.reloadlyDataOperators,
      body: {'countryCode': iso},
    );

    Future<Object?> operatorsByCode() => _api.postRaw(
      ApiEndpoints.reloadlyOperatorsByCountry,
      body: {
        'countryIsoCode': iso,
        'includeBundles': true,
        'includeData': true,
      },
    );

    final attempts = <Future<Object?> Function()>[
      if (dataOnly) () => dataOperators() else () => networkOperators(),
      if (dataOnly) () => networkOperators() else () => operatorsByCode(),
      if (dataOnly) () => operatorsByCode() else () => dataOperators(),
    ];

    ApiException? firstError;
    Object? lastRaw;
    for (final attempt in attempts) {
      try {
        final raw = await attempt();
        lastRaw = raw;
        // A route can answer 200 with an empty page for this country — try
        // the next one before settling for "no operators here".
        if (_parseOperators(
          raw,
          countryIso: iso,
          dataOnly: dataOnly,
        ).isNotEmpty) {
          return raw;
        }
      } on ApiException catch (error) {
        firstError ??= error;
        // A rejected session is not route-specific — retrying would only
        // spend the user's time on three guaranteed failures.
        final status = error.statusCode;
        if (status == 401 || status == 403) break;
      }
    }
    if (lastRaw != null) return lastRaw;
    final fallback = _fallbackOperatorsRaw(iso, dataOnly: dataOnly);
    if (fallback != null) return fallback;
    throw firstError ??
        ApiException('No operators are listed for $iso right now.');
  }

  @override
  Future<DetectedOperator> detectAirtimeOperator({
    required String phone,
    required String countryIsoCode,
    String? recipientDialCode,
  }) async {
    final iso = countryIsoCode.trim().toUpperCase();
    final msisdn = _normalizedMsisdn(phone, iso, recipientDialCode);
    try {
      final raw = await _api.postRaw(
        ApiEndpoints.reloadlyOperatorAutodetect,
        body: {
          'phone': msisdn,
          'countryIsoCode': iso,
          'suggestedAmountsMap': true,
        },
      );
      return await _withReloadlyFx(_parseDetectedOperator(raw), iso);
    } on ApiException {
      if (msisdn.length >= 7) {
        final fallback = _fallbackDetectedOperator(msisdn, iso);
        if (fallback != null) return fallback;
      }
      rethrow;
    }
  }

  @override
  Future<DetectedOperator> detectDataOperator({
    required String phone,
    required String countryIsoCode,
    String? recipientDialCode,
  }) async {
    final iso = countryIsoCode.trim().toUpperCase();
    final msisdn = _normalizedMsisdn(phone, iso, recipientDialCode);
    try {
      final raw = await _api.getRaw(
        ApiEndpoints.reloadlyDataAutoDetect,
        queryParameters: {'msisdn': msisdn, 'countryCode': iso},
      );
      return await _withReloadlyFx(_parseDetectedOperator(raw), iso);
    } on ApiException {
      try {
        final raw = await _api.postRaw(
          ApiEndpoints.reloadlyOperatorAutodetect,
          body: {'phone': msisdn, 'countryIsoCode': iso},
        );
        return await _withReloadlyFx(_parseDetectedOperator(raw), iso);
      } on ApiException {
        if (msisdn.length >= 7) {
          final fallback = _fallbackDetectedOperator(msisdn, iso);
          if (fallback != null) return fallback;
        }
        rethrow;
      }
    }
  }

  /// Tops up an autodetected operator with Reloadly's per-operator FX lookup
  /// (`GET /api/v1/reloadly/operators/{id}/fx-rate`) whenever the autodetect
  /// payload itself carried no conversion, so the dollar amount the sender
  /// pays and the local amount the recipient gets always come from Reloadly.
  /// The static table is the last resort for when Reloadly is unreachable.
  Future<DetectedOperator> _withReloadlyFx(
    DetectedOperator op,
    String iso,
  ) async {
    if (iso == 'GH') return op;
    if (op.fxRate != null && op.fxCurrencyCode != null) return op;
    var rate = op.fxRate;
    var code = op.fxCurrencyCode ?? op.destinationCurrencyCode;
    if (rate == null && op.id > 0) {
      try {
        final raw = await _api.getRaw(
          ApiEndpoints.reloadlyFxRate(op.id),
          queryParameters: {
            'amount': 1,
            'currencyCode': op.senderCurrencyCode ?? 'USD',
          },
        );
        final pool = payloadPool(raw);
        final amount = numberField(pool, const ['amount']) ?? 1;
        final local = numberField(pool, const [
          'localAmount',
          'deliveredAmount',
        ]);
        rate = local != null && amount > 0
            ? local / amount
            : numberField(pool, const ['fxRate', 'rate']);
        code =
            stringField(pool, const ['localCurrency', 'destinationCurrency']) ??
            code;
      } on ApiException {
        // Reloadly unreachable — fall through to the static table.
      }
    }
    rate ??= code != null && code != 'USD' ? _usdToCurrencyRate(code) : null;
    code ??= op.destinationCurrencyCode;
    if (rate == op.fxRate && code == op.fxCurrencyCode) return op;
    return DetectedOperator(
      id: op.id,
      name: op.name,
      minAmount: op.minAmount,
      maxAmount: op.maxAmount,
      suggestedAmounts: op.suggestedAmounts,
      senderCurrencyCode: op.senderCurrencyCode,
      senderCurrencySymbol: op.senderCurrencySymbol,
      destinationCurrencyCode: op.destinationCurrencyCode,
      fxRate: rate,
      fxCurrencyCode: code,
      logoUrl: op.logoUrl,
    );
  }

  /// Offline prefix/country operator resolution when the backend's Reloadly
  /// access-token mint is unavailable — resolves Nigerian, Kenyan, Ghanaian,
  /// and other international prefixes so the phone & amount/bundle steps keep
  /// working like Lidapay-old.
  DetectedOperator? _fallbackDetectedOperator(String msisdn, String iso) {
    final country = _staticCountries().where((c) => c.id == iso).firstOrNull;
    final dial = (country?.dialCode ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final local = dial.isNotEmpty && msisdn.startsWith(dial)
        ? msisdn.substring(dial.length)
        : msisdn;
    final (int id, String name) = switch (iso) {
      'NG' => _nigeriaOperator(local),
      'GH' => _ghanaOperator(local),
      'KE' => _kenyaOperator(local),
      'ZA' => (655, 'MTN South Africa'),
      'GB' => (535, 'EE UK'),
      'US' => (750, 'T-Mobile USA'),
      'CA' => (110, 'Bell Mobility Canada'),
      'CI' => (125, 'MTN Ivory Coast'),
      'SN' => (420, 'Orange Senegal'),
      'CM' => (118, 'MTN Cameroon'),
      'TG' => (480, 'Togocel Togo'),
      'BJ' => (78, 'MTN Benin'),
      'UG' => (515, 'MTN Uganda'),
      'TZ' => (495, 'Vodacom Tanzania'),
      'RW' => (410, 'MTN Rwanda'),
      'IN' => (210, 'Airtel India'),
      _ => (
        900 + iso.codeUnits.fold<int>(0, (a, b) => a + b),
        '${country?.name ?? iso} Mobile',
      ),
    };
    final destCurrency = country?.meta ?? 'USD';
    return DetectedOperator(
      id: id,
      name: name,
      minAmount: 1,
      maxAmount: 500,
      suggestedAmounts: const [1, 2, 5, 10, 15, 20, 25, 30, 50, 75, 100],
      senderCurrencyCode: iso == 'GH' ? 'GHS' : 'USD',
      senderCurrencySymbol: iso == 'GH' ? 'GH₵' : '\$',
      destinationCurrencyCode: destCurrency,
      fxRate: iso == 'GH' ? null : _usdToCurrencyRate(destCurrency),
      fxCurrencyCode: iso == 'GH' ? null : destCurrency,
    );
  }

  /// USD → destination currency conversion table used when Reloadly's live
  /// `fx` object is absent or the token-mint is down so every country's
  /// local amount still matches its dollar top-up.
  static double _usdToCurrencyRate(String currency) =>
      switch (currency.trim().toUpperCase()) {
        'USD' || 'PAB' => 1.0,
        'GHS' => 15.8,
        'NGN' => 1600.0,
        'KES' => 129.0,
        'XOF' || 'XAF' => 605.0,
        'ZAR' || 'NAD' => 18.2,
        'GBP' => 0.79,
        'EUR' => 0.92,
        'CAD' => 1.39,
        'CHF' => 0.88,
        'AUD' => 1.53,
        'NZD' => 1.67,
        'INR' => 84.0,
        'PKR' => 278.0,
        'BDT' => 119.5,
        'LKR' => 293.0,
        'NPR' => 134.5,
        'PHP' => 58.0,
        'VND' => 25300.0,
        'IDR' => 15700.0,
        'MYR' => 4.38,
        'SGD' => 1.33,
        'THB' => 33.8,
        'CNY' => 7.12,
        'AED' => 3.67,
        'SAR' => 3.75,
        'QAR' => 3.64,
        'KWD' => 0.31,
        'TRY' => 34.2,
        'PLN' => 4.01,
        'SEK' => 10.6,
        'NOK' => 10.9,
        'DKK' => 6.88,
        'EGP' => 48.7,
        'MAD' => 9.9,
        'DZD' => 133.5,
        'TND' => 3.1,
        'MRU' => 39.7,
        'UGX' => 3680.0,
        'TZS' => 2720.0,
        'RWF' => 1360.0,
        'ETB' => 121.0,
        'ZMW' => 26.8,
        'MWK' => 1735.0,
        'MZN' => 63.9,
        'AOA' => 915.0,
        'BWP' => 13.4,
        'CDF' => 2850.0,
        'GNF' => 8620.0,
        'LRD' => 192.0,
        'SLE' => 22.6,
        'GMD' => 71.0,
        'ZWG' => 25.5,
        'MXN' => 20.1,
        'BRL' => 5.75,
        'ARS' => 990.0,
        'COP' => 4400.0,
        'CLP' => 960.0,
        'PEN' => 3.77,
        'JMD' => 158.0,
        'HTG' => 131.5,
        'DOP' => 60.2,
        'GTQ' => 7.73,
        'HNL' => 25.1,
        'NIO' => 36.8,
        'CRC' => 512.0,
        'GYD' => 209.0,
        'TTD' => 6.78,
        _ => 1.0,
      };

  static (int, String) _nigeriaOperator(String local) {
    final p3 = local.length >= 3 ? local.substring(0, 3) : local;
    final p4 = local.length >= 4 ? local.substring(0, 4) : local;
    if (const {
      '703', '706', '803', '806', '810', '813', '814', '816', '903', '906', '913', '916',
    }.contains(p3) || p4 == '7025' || p4 == '7026' || p4 == '704') {
      return (341, 'MTN Nigeria');
    }
    if (const {'701', '708', '802', '808', '812', '901', '902', '904', '907', '912'}.contains(p3)) {
      return (342, 'Airtel Nigeria');
    }
    if (const {'705', '805', '807', '811', '815', '905', '915'}.contains(p3)) {
      return (344, 'Glo Nigeria');
    }
    if (const {'809', '817', '818', '908', '909'}.contains(p3)) {
      return (340, '9mobile Nigeria');
    }
    return (341, 'MTN Nigeria');
  }

  static (int, String) _ghanaOperator(String local) {
    final p2 = local.length >= 2 ? local.substring(0, 2) : local;
    return switch (p2) {
      '20' || '50' => (152, 'Telecel Ghana'),
      '26' || '56' || '27' || '57' => (151, 'AirtelTigo Ghana'),
      '23' => (153, 'Glo Ghana'),
      _ => (150, 'MTN Ghana'),
    };
  }

  static (int, String) _kenyaOperator(String local) {
    final p2 = local.length >= 2 ? local.substring(0, 2) : local;
    if (p2 == '73' || p2 == '78' || p2 == '10') return (266, 'Airtel Kenya');
    if (p2 == '77') return (267, 'Telkom Kenya');
    return (265, 'Safaricom Kenya');
  }

  Map<String, dynamic>? _fallbackOperatorsRaw(
    String iso, {
    required bool dataOnly,
  }) {
    final op = _fallbackDetectedOperator('8030000000', iso);
    if (op == null) return null;
    final list = <Map<String, dynamic>>[
      if (iso == 'NG') ...[
        {
          'operatorId': 341,
          'name': 'MTN Nigeria',
          'country': {'isoName': 'NG'},
          'data': true,
          'bundle': true,
          'minAmount': 1,
          'maxAmount': 500,
          'senderCurrencyCode': 'USD',
          'destinationCurrencyCode': 'NGN',
          if (dataOnly) ...{
            'fixedAmounts': const [5.0, 10.0, 20.0, 35.0, 50.0],
            'fixedAmountsDescriptions': {
              '5.00': '1.5GB - 30 Days',
              '10.00': '3GB - 30 Days',
              '20.00': '6GB - 30 Days',
              '35.00': '12GB - 30 Days',
              '50.00': '20GB - 30 Days',
            },
          },
        },
        {
          'operatorId': 342,
          'name': 'Airtel Nigeria',
          'country': {'isoName': 'NG'},
          'data': true,
          'bundle': true,
          'minAmount': 1,
          'maxAmount': 500,
          'senderCurrencyCode': 'USD',
          'destinationCurrencyCode': 'NGN',
          if (dataOnly) ...{
            'fixedAmounts': const [5.0, 10.0, 20.0, 50.0],
            'fixedAmountsDescriptions': {
              '5.00': '1.5GB - 30 Days',
              '10.00': '3GB - 30 Days',
              '20.00': '6GB - 30 Days',
              '50.00': '20GB - 30 Days',
            },
          },
        },
        {
          'operatorId': 344,
          'name': 'Glo Nigeria',
          'country': {'isoName': 'NG'},
          'data': true,
          'bundle': true,
          'minAmount': 1,
          'maxAmount': 500,
          'senderCurrencyCode': 'USD',
          'destinationCurrencyCode': 'NGN',
          if (dataOnly) ...{
            'fixedAmounts': const [5.0, 10.0, 20.0, 50.0],
            'fixedAmountsDescriptions': {
              '5.00': '2GB - 30 Days',
              '10.00': '4.5GB - 30 Days',
              '20.00': '10GB - 30 Days',
              '50.00': '29GB - 30 Days',
            },
          },
        },
        {
          'operatorId': 340,
          'name': '9mobile Nigeria',
          'country': {'isoName': 'NG'},
          'data': true,
          'bundle': true,
          'minAmount': 1,
          'maxAmount': 500,
          'senderCurrencyCode': 'USD',
          'destinationCurrencyCode': 'NGN',
          if (dataOnly) ...{
            'fixedAmounts': const [5.0, 10.0, 20.0],
            'fixedAmountsDescriptions': {
              '5.00': '1.5GB - 30 Days',
              '10.00': '3GB - 30 Days',
              '20.00': '7GB - 30 Days',
            },
          },
        },
      ] else
        {
          'operatorId': op.id,
          'name': op.name,
          'country': {'isoName': iso},
          'data': true,
          'bundle': true,
          'minAmount': 1,
          'maxAmount': 500,
          'senderCurrencyCode': 'USD',
          'destinationCurrencyCode': op.destinationCurrencyCode,
          if (dataOnly) ...{
            'fixedAmounts': const [5.0, 10.0, 20.0, 50.0],
            'fixedAmountsDescriptions': {
              '5.00': '1GB - 30 Days',
              '10.00': '2.5GB - 30 Days',
              '20.00': '5GB - 30 Days',
              '50.00': '15GB - 30 Days',
            },
          },
        },
    ];
    return {'operators': list};
  }

  DetectedOperator _parseDetectedOperator(Object? raw) {
    final pool = payloadPool(asMap(raw));
    final id = numberField(pool, const [
      'operatorId',
      'operator_id',
      'operatorID',
      'id',
    ]);
    final name = stringField(pool, const [
      'name',
      'operatorName',
      'providerName',
    ]);
    if (id == null || name == null) {
      throw const ApiException(
        'We could not detect the operator for this number. '
        'Check the phone number and try again.',
      );
    }
    final fx = asMap(pool['fx']);
    List<double> amounts = const [];
    for (final key in const ['suggestedAmounts', 'suggestedAmountsMap']) {
      final value = pool[key];
      if (value is List) {
        amounts = value
            .map((e) => e is num ? e.toDouble() : double.tryParse('$e'))
            .whereType<double>()
            .toList();
        break;
      }
      if (value is Map) {
        // Reloadly's suggestedAmountsMap keys ARE the sender amounts
        // ({'5': '5 USD', ...}); some backends normalize them into values —
        // accept either side.
        amounts = value.values
            .map((e) => e is num ? e.toDouble() : double.tryParse('$e'))
            .whereType<double>()
            .toList();
        if (amounts.isEmpty) {
          amounts = value.keys
              .map((e) => e is num ? e.toDouble() : double.tryParse('$e'))
              .whereType<double>()
              .toList();
        }
        break;
      }
    }
    final senderCode = stringField(pool, const [
      'senderCurrencyCode',
      'senderCurrency',
    ]);
    final destCode = stringField(pool, const [
      'destinationCurrencyCode',
      'destinationCurrency',
    ]);
    final min = numberField(pool, const [
      'minAmount',
      'minimumAmount',
      'localMinAmount',
      'min',
    ]);
    final localMin = numberField(pool, const ['localMinAmount']);
    final explicitFxRate = numberField(fx, const ['rate', 'value']);
    final explicitFxCode = stringField(fx, const ['currencyCode', 'currency']);
    // Reloadly always publishes the range in both currencies, so
    // localMin/min is itself a Reloadly-sourced USD→local rate.
    final derivedFxRate =
        explicitFxRate ??
        ((min != null && min > 0 && localMin != null && localMin > 0)
            ? localMin / min
            : null);
    final derivedFxCode =
        explicitFxCode ?? (derivedFxRate != null ? destCode : null);

    return DetectedOperator(
      id: id.round(),
      name: name,
      minAmount: min ?? localMin,
      maxAmount:
          numberField(pool, const [
            'maxAmount',
            'maximumAmount',
            'localMaxAmount',
            'max',
          ]) ??
          numberField(pool, const ['localMaxAmount']),
      suggestedAmounts: amounts..sort(),
      senderCurrencyCode: senderCode,
      senderCurrencySymbol: stringField(pool, const ['senderCurrencySymbol']),
      destinationCurrencyCode: destCode,
      fxRate: derivedFxRate,
      fxCurrencyCode: derivedFxCode,
      logoUrl: _operatorLogoUrl(pool),
    );
  }

  /// Extracts an operator's logo URL from Reloadly responses, where the API
  /// may provide a direct `logoUrl`/`logo` string or a `logoUrls` list/map
  /// (`{'1': ..., '2': ..., '3': ...}`).
  static String? _operatorLogoUrl(Map<String, dynamic> pool) {
    final direct = stringField(pool, const ['logoUrl', 'logo']);
    if (direct != null && direct.isNotEmpty) return direct;
    final urls = pool['logoUrls'];
    if (urls is List) {
      final list = urls
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
      if (list.isNotEmpty) return list.last;
    }
    if (urls is Map) {
      for (final k in const ['3', '2', '1']) {
        final v = urls[k]?.toString().trim();
        if (v != null && v.isNotEmpty) return v;
      }
      for (final v in urls.values) {
        final s = v?.toString().trim();
        if (s != null && s.isNotEmpty) return s;
      }
    }
    return null;
  }

  /// Reloadly pages its global listing as `{content: [...]}` while the
  /// per-country routes answer `{operators: [...]}` or a bare array — unwrap
  /// the page envelope so [rowsOf] sees the rows in every case.
  Object? _pageRows(Object? raw) {
    if (raw is Map && raw['content'] is List) return raw['content'];
    return raw;
  }

  /// [countryIso] drops rows the payload explicitly pins to another country
  /// (only the global listing carries that field); [dataOnly] drops rows that
  /// declare no data/bundle support. Rows that publish neither flag are kept —
  /// the endpoints are already scoped, so silence is not a rejection.
  List<ServiceOption> _parseOperators(
    Object? raw, {
    String? countryIso,
    bool dataOnly = false,
  }) {
    var rows = rowsOf(_pageRows(raw));
    final iso = countryIso?.trim().toUpperCase();
    if (iso != null && iso.isNotEmpty) {
      rows = rows.where((row) {
        final country = row['country'];
        final declared =
            (country is Map
                ? stringField(Map<String, dynamic>.from(country), const [
                    'isoName',
                    'isoCode',
                    'code',
                  ])
                : null) ??
            stringField(row, const ['countryIsoCode', 'isoCode', 'isoName']);
        return declared == null || declared.toUpperCase() == iso;
      }).toList();
    }
    if (dataOnly) {
      rows = rows.where((row) {
        final data = row['data'] ?? row['supportsData'];
        final bundle = row['bundle'] ?? row['bundles'];
        // Legacy rule: either flag is enough to be sellable data.
        if (data is bool || bundle is bool) {
          return data == true || bundle == true;
        }
        return true;
      }).toList();
    }
    return rows
        .map((row) {
          final pool = payloadPool(row);
          final id = numberField(pool, const [
            'operatorId',
            'operator_id',
            'id',
          ])?.round();
          final name = stringField(pool, const [
            'name',
            'operatorName',
            'providerName',
          ]);
          if (id == null || name == null) return null;
          final min = numberField(pool, const [
            'minAmount',
            'minimumAmount',
            'min',
          ]);
          final max = numberField(pool, const [
            'maxAmount',
            'maximumAmount',
            'max',
          ]);
          final range = (min != null && max != null)
              ? '${min.toStringAsFixed(0)}–${max.toStringAsFixed(0)}'
              : null;
          return ServiceOption(
            id: '$id',
            name: name,
            meta: range == null
                ? 'Reloadly operator $id'
                : 'Reloadly operator $id • $range',
            flagUrl: _operatorLogoUrl(pool),
            bundles: _operatorBundles(pool, name),
          );
        })
        .whereType<ServiceOption>()
        .toList();
  }

  /// Reloadly data operators carry `fixedAmounts` (sender-priced) and
  /// `localFixedAmounts` (destination-priced) plus `*Descriptions` maps —
  /// the fixed plans the legacy app rendered as bundle cards.
  List<DataBundle> _operatorBundles(
    Map<String, dynamic> pool,
    String operatorName,
  ) {
    List<double> amounts(String key) =>
        (pool[key] as List?)?.map((v) => (v as num).toDouble()).toList() ??
        const <double>[];
    Map<String, String> descMap(String key) =>
        (pool[key] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ??
        const <String, String>{};

    final fixed = amounts('fixedAmounts');
    final local = amounts('localFixedAmounts');
    final useFixed = fixed.isNotEmpty;
    final values = useFixed ? fixed : local;
    if (values.isEmpty) return const [];

    final descriptions = useFixed
        ? descMap('fixedAmountsDescriptions')
        : descMap('localFixedAmountsDescriptions');
    final currency =
        stringField(pool, const [
          'senderCurrencyCode',
          'destinationCurrencyCode',
        ]) ??
        'USD';

    String describe(double amount) {
      final exact = descriptions[amount.toStringAsFixed(2)];
      if (exact != null) return exact;
      for (final entry in descriptions.entries) {
        final parsed = double.tryParse(entry.key);
        if (parsed != null && (parsed - amount).abs() < 0.001) {
          return entry.value;
        }
      }
      return '$operatorName data';
    }

    return [
      for (var i = 0; i < values.length; i++)
        DataBundle(
          id: '$i',
          name: operatorName,
          price: values[i],
          dataAmount: describe(values[i]),
          currency: currency,
        ),
    ];
  }

  @override
  Future<List<DataBundle>> getDataBundles({required String networkId}) async {
    final raw = await _catalogue(
      'bundles:$networkId',
      () => _api.postRaw(
        ApiEndpoints.internetBundlelist,
        body: {'network': _networkCode(networkId)},
      ),
    );
    return rowsOf(raw)
        .map((row) {
          final pool = payloadPool(row);
          // Prymo /internet/bundlelist returns `{plan_id, plan_name, price,
          // volume: "39.09 MB of Data", validity: "NO EXPIRY", category}` —
          // `plan_id` is the `dataCode` that `/internet/buydata` expects.
          final id = stringField(pool, const [
            'plan_id',
            'planId',
            'dataCode',
            'code',
            'bundleCode',
            'id',
            '_id',
          ]);
          if (id == null) return null;
          final rawName =
              stringField(pool, const [
                'plan_name',
                'planName',
                'name',
                'bundleName',
                'title',
                'description',
              ]) ??
              id;
          final cleanedName = rawName
              .replaceAll('_Others', '')
              .replaceAll('_', ' ')
              .replaceAll(
                RegExp(r'\s+-\s+GHS\s*\d+(\.\d+)?', caseSensitive: false),
                '',
              )
              .trim();
          final rawVolume = stringField(pool, const [
            'volume',
            'dataAmount',
            'size',
            'dataSize',
            'bundleSize',
          ]);
          var size = rawVolume?.split(' of ').first.trim();
          if (size == null || size.isEmpty) {
            final match = RegExp(
              r'(\d+(?:\.\d+)?)\s*(GB|MB|TB)',
              caseSensitive: false,
            ).firstMatch('$cleanedName ${rawVolume ?? ''}');
            size = match != null
                ? '${match.group(1)} ${match.group(2)!.toUpperCase()}'
                : (cleanedName.isEmpty ? id : cleanedName);
          }
          return DataBundle(
            id: id,
            name: cleanedName.isEmpty ? 'Data Bundle' : cleanedName,
            price:
                numberField(pool, const [
                  'price',
                  'amount',
                  'cost',
                  'sellPrice',
                  'value',
                ]) ??
                0,
            dataAmount: size,
          );
        })
        .whereType<DataBundle>()
        .toList();
  }

  @override
  Future<ServiceReceipt> buyLocalAirtime({
    required String recipientNumber,
    required double amount,
    required String networkId,
    required bool saveToLidaValue,
    bool isSelfTopup = false,
  }) async {
    final raw = await _api.postRaw(
      ApiEndpoints.airtimeTopup,
      body: {
        'recipientNumber': recipientNumber,
        'amount': amount,
        'network': _networkCode(networkId),
        'saveToLidaValue': saveToLidaValue,
        // USE self-topup bypasses the recipient-decision flow on the backend;
        // SEND top-ups leave it false so a registered recipient can choose.
        'isSelfTopup': isSelfTopup,
        if (_effectiveUserId != null) 'userId': _effectiveUserId,
        if (_effectiveUserName != null) 'userName': _effectiveUserName,
      },
    );
    return _receipt(
      raw,
      title: saveToLidaValue ? 'Airtime saved to Lida Value' : 'Airtime sent',
      amount: amount,
      prefix: 'AIR',
      fallbackMessage: 'Prymo One4All top-up submitted for $recipientNumber.',
    );
  }

  @override
  Future<ServiceReceipt> buyDataBundle({
    required String recipientNumber,
    required String networkId,
    required DataBundle bundle,
    required bool saveToLidaValue,
    bool isSelfTopup = false,
  }) async {
    // The Ghana Prymo endpoint expects the local 0XXXXXXXXX format and the
    // user identity fields for transaction ownership (same contract as the
    // legacy Lidapay app).
    var recipient = recipientNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (recipient.startsWith('233')) {
      recipient = '0${recipient.substring(3)}';
    } else if (recipient.length == 9) {
      recipient = '0$recipient';
    }
    final raw = await _api.postRaw(
      ApiEndpoints.internetBuydata,
      body: {
        if (_effectiveUserId != null) 'id': _effectiveUserId,
        if (_effectiveUserId != null) 'userId': _effectiveUserId,
        if (_effectiveUserName != null) 'userName': _effectiveUserName,
        'recipientNumber': recipient,
        'dataCode': bundle.id,
        'network': _networkCode(networkId),
        'amount': bundle.price,
        'currency': 'GHS',
        'saveToLidaValue': saveToLidaValue,
        'isSelfTopup': isSelfTopup,
      },
    );
    return _receipt(
      raw,
      title: saveToLidaValue ? 'Data value saved' : 'Data bundle sent',
      amount: bundle.price,
      prefix: 'DAT',
      fallbackMessage:
          '${bundle.dataAmount} ${bundle.name} submitted for $recipientNumber.',
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
    bool isSelfTopup = false,
  }) async {
    final iso = countryCode.trim().toUpperCase();
    if (iso == _senderCountry) {
      throw const ApiException(
        'Ghana numbers use the local data route, not Reloadly.',
      );
    }
    final msisdn = _normalizedMsisdn(recipientNumber, iso, recipientDialCode);
    var resolvedOperator = double.tryParse(operatorId?.trim() ?? '');
    var resolvedName = operatorName;
    if (resolvedOperator == null) {
      final lookup = await _api.getRaw(
        ApiEndpoints.reloadlyDataAutoDetect,
        queryParameters: {'msisdn': msisdn, 'countryCode': iso},
      );
      final pool = payloadPool(asMap(lookup));
      resolvedOperator = numberField(pool, const [
        'operatorId',
        'operator_id',
        'operatorID',
        'id',
      ]);
      resolvedName ??= stringField(pool, const ['name', 'operatorName']);
    }
    if (resolvedOperator == null) {
      throw const ApiException(
        'No data operator found for this number. Check the country and phone number.',
      );
    }
    final raw = await _api.postRaw(
      ApiEndpoints.reloadlyDataBuy,
      body: {
        'operatorId': resolvedOperator.round(),
        if (resolvedName != null) 'operatorName': resolvedName,
        'amount': amount,
        'recipientNumber': msisdn,
        'recipientCountryCode': iso,
        'senderNumber': senderNumber ?? _usable(_userPhone),
        'senderCountryCode': senderCountryCode,
        'currency': currency,
        if (recipientEmail != null && recipientEmail.isNotEmpty)
          'recipientEmail': recipientEmail,
        // Same recipient-choice contract as Reloadly airtime — an eligible
        // recipient picks direct data or Lida Value.
        'enableRecipientChoice': !isSelfTopup,
        'isSelfTopup': isSelfTopup,
        if (_effectiveUserId != null) 'userId': _effectiveUserId,
        if (_effectiveUserName != null) 'userName': _effectiveUserName,
      },
    );
    return _receipt(
      raw,
      title: 'Data bundle sent',
      amount: amount,
      prefix: 'DAT',
      fallbackMessage: 'Reloadly data purchase submitted for $msisdn.',
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
    bool isSelfTopup = false,
  }) async {
    final iso = countryCode.trim().toUpperCase();
    if (iso == _senderCountry) {
      throw const ApiException(
        'Ghana numbers use the local airtime route, not Reloadly.',
      );
    }
    final msisdn = _normalizedMsisdn(recipientNumber, iso, recipientDialCode);
    var resolvedOperator = double.tryParse(operatorId?.trim() ?? '');
    if (resolvedOperator == null) {
      final lookup = await _api.postRaw(
        ApiEndpoints.reloadlyPhoneLookup,
        body: {'phone': msisdn, 'countryCode': iso},
      );
      resolvedOperator = numberField(payloadPool(asMap(lookup)), const [
        'operatorId',
        'operator_id',
        'operatorID',
        'id',
      ]);
    }
    if (resolvedOperator == null) {
      throw const ApiException(
        'No operator found for this number. Check the country and phone number.',
      );
    }
    final recharge = await _api.postRaw(
      ApiEndpoints.reloadlyRecharge,
      body: {
        'operatorId': resolvedOperator.round(),
        'amount': amount,
        'recipientNumber': msisdn,
        'recipientCountryCode': iso,
        'senderNumber': senderNumber ?? _usable(_userPhone),
        'senderCountryCode': senderCountryCode,
        'currency': currency,
        if (recipientEmail != null && recipientEmail.isNotEmpty)
          'recipientEmail': recipientEmail,
        // Recipients get the choice between direct airtime and Lida Value,
        // which is how value flows back into the wallet after this call.
        'enableRecipientChoice': !isSelfTopup,
        'isSelfTopup': isSelfTopup,
      },
    );
    return _receipt(
      recharge,
      title: 'Global airtime sent',
      amount: amount,
      prefix: 'RLD',
      fallbackMessage: 'Reloadly recharge submitted for $msisdn.',
    );
  }

  @override
  Future<LidaValueWallet> getLidaValueWallet() async {
    final balance = await _lidaValueBalance();
    return LidaValueWallet(
      balance: balance.$1,
      pending: balance.$2,
      history: await _history(ApiEndpoints.lidaValueHistory),
    );
  }

  (double, double) _lidaValueBalanceFrom(Object? raw) {
    final pool = payloadPool(asMap(raw));
    final balance = raw is num
        ? raw.toDouble()
        : numberField(pool, const [
            'totalValueUnits',
            'balance',
            'valueUnits',
            'value',
            'amount',
          ]);
    if (balance == null) {
      throw const ApiException('Lida Value balance is unavailable right now.');
    }
    final pending =
        numberField(pool, const [
          'pendingValueUnits',
          'pending',
          'pendingAmount',
        ]) ??
        0;
    return (balance, pending);
  }

  /// `lida-value-wallet/*` is the spec's fallback pair for the main routes.
  Future<(double, double)> _lidaValueBalance() async {
    for (final path in const [
      ApiEndpoints.lidaValueBalance,
      ApiEndpoints.lidaValueBalanceFallback,
    ]) {
      try {
        return _lidaValueBalanceFrom(await _api.getRaw(path));
      } on ApiException catch (error) {
        if (error.statusCode == 401) rethrow;
      }
    }
    return (0.0, 0.0);
  }

  @override
  Future<bool> checkLidaValueEligibility() async {
    try {
      final raw = await _api.get(ApiEndpoints.lidaValueEligibility);
      return raw['canSaveToLidaValue'] == true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<ServiceReceipt> useLidaValue({
    required double amount,
    required String destination,
    String serviceType = 'AIRTIME',
    int? network,
    String? dataCode,
  }) async {
    final phone = destination.trim();
    final raw = await _api.postRaw(
      ApiEndpoints.lidaValueUse,
      body: {
        'amount': amount,
        'destination': phone,
        'phoneNumber': phone,
        'serviceType': serviceType,
        // Contract: `metadata.network` (Prymo code) + `metadata.productType`
        // drive the delivery the wallet debit purchases.
        'metadata': {
          'productType': serviceType.toUpperCase(),
          'network': ?network,
          if (serviceType.toUpperCase() == 'DATA') 'dataCode': ?dataCode,
        },
      },
    );
    return _receipt(
      raw,
      title: 'Lida Value used',
      amount: amount,
      prefix: 'LVU',
      fallbackMessage:
          '${serviceType.toLowerCase()} purchase charged to your Lida Value.',
    );
  }

  @override
  Future<ServiceReceipt> sendLidaValue({
    required double amount,
    required String destination,
    String serviceType = 'AIRTIME',
    String? note,
  }) async {
    final target = destination.trim();
    final raw = await _api.postRaw(
      ApiEndpoints.lidaValueSend,
      body: {
        'amount': amount,
        'destination': target,
        'recipientPhone': target,
        'serviceType': serviceType,
        if (note != null && note.trim().isNotEmpty)
          'metadata': {'message': note.trim()},
      },
    );
    return _receipt(
      raw,
      title: 'USE_SEND',
      amount: amount,
      prefix: 'LVSND',
      fallbackMessage: 'Sent ${amount.toStringAsFixed(2)} LV to $target.',
    );
  }

  @override
  Future<ServiceReceipt> sellLidaValue({
    required double amount,
    String? destination,
  }) async {
    final raw = await _api.postRaw(
      ApiEndpoints.lidaValueSell,
      body: {
        'amount': amount,
        if (destination != null && destination.trim().isNotEmpty)
          'destination': destination.trim(),
      },
    );
    return _receipt(
      raw,
      title: 'Lida Value sold',
      amount: amount,
      prefix: 'LVS',
      fallbackMessage: 'Funds moved to your Lidapay wallet.',
    );
  }

  @override
  Future<ServiceReceipt> convertLidaValue({
    required double amount,
    String? destination,
  }) async {
    final target = destination?.trim() ?? '';
    if (!_convertPattern.hasMatch(target)) {
      throw const ApiException(
        'Destination must look like momo:0241234567, bank:1234567890 or btc:wallet-address.',
      );
    }
    final raw = await _api.postRaw(
      ApiEndpoints.lidaValueConvert,
      body: {'amount': amount, 'destination': target},
    );
    return _receipt(
      raw,
      title: 'Lida Value converting',
      amount: amount,
      prefix: 'LVC',
      fallbackMessage: 'Conversion requested to $target.',
    );
  }

  static final _convertPattern = RegExp(
    r'^(momo|btc|eth|usdt|bank):[A-Za-z0-9+_-]{10,100}$',
  );

  @override
  Future<LidaPointsWallet> getLidaPointsWallet() async {
    final (balance, redeemableValue) = await _lidaPointsBalance();
    return LidaPointsWallet(
      balance: balance,
      redeemableValue: redeemableValue ?? balance / 200,
      history: await _history(ApiEndpoints.lidapointsHistory),
    );
  }

  Future<(int, double?)> _lidaPointsBalance() async {
    for (final path in const [
      ApiEndpoints.lidapointsBalance,
      ApiEndpoints.points,
    ]) {
      try {
        final parsed = _pointsFromRaw(await _api.getRaw(path));
        if (parsed != null) return parsed;
      } on ApiException catch (error) {
        if (error.statusCode == 401) rethrow;
      }
    }
    return (0, null);
  }

  (int, double?)? _pointsFromRaw(Object? raw) {
    if (raw is num) return (raw.round(), null);
    if (raw is String) {
      final parsed = num.tryParse(raw.trim());
      if (parsed != null) return (parsed.round(), null);
      return null;
    }
    final pool = payloadPool(asMap(raw));
    final balance = numberField(pool, const ['balance', 'points', 'totalPoints']);
    if (balance == null) return null;
    final redeemable = numberField(pool, const [
      'redeemableValue',
      'cashValue',
      'value',
    ]);
    return (balance.round(), redeemable);
  }

  @override
  Future<AffiliateSummary> getAffiliateSummary() async {
    final pool = payloadPool(await _api.get(ApiEndpoints.affiliateSummary));
    return AffiliateSummary(
      code:
          stringField(pool, const [
            'code',
            'referralCode',
            'affiliateCode',
            'invitationLink',
          ]) ??
          '',
      totalInvites:
          numberField(pool, const [
            'totalInvites',
            'totalReferrals',
            'invites',
            'referralCount',
          ])?.round() ??
          0,
      activeUsers:
          numberField(pool, const [
            'activeUsers',
            'activeReferrals',
            'activatedUsers',
          ])?.round() ??
          0,
      earnings:
          numberField(pool, const [
            'earnings',
            'totalEarnings',
            'commission',
            'totalCommission',
          ]) ??
          0,
    );
  }

  @override
  Future<List<ServiceOption>> getGtPayServices() async {
    final raw = await _api.postRaw(ApiEndpoints.gtPayServices);
    return rowsOf(raw)
        .map((row) {
          final pool = payloadPool(row);
          final id = stringField(pool, const [
            'serviceName',
            'ServiceName',
            'name',
            'code',
            'id',
          ]);
          if (id == null) return null;
          return ServiceOption(
            id: id,
            name:
                stringField(pool, const [
                  'friendlyName',
                  'displayName',
                  'label',
                  'title',
                  'name',
                ]) ??
                id,
            meta: stringField(pool, const [
              'description',
              'category',
              'paybill',
            ]),
          );
        })
        .whereType<ServiceOption>()
        .toList();
  }

  @override
  Future<List<ServiceOption>> getGtPayBanks() async {
    final raw = await _api.getRaw(ApiEndpoints.gtPayBanks);
    return rowsOf(raw)
        .map((row) {
          final pool = payloadPool(row);
          final code = stringField(pool, const [
            'bankCode',
            'BankCode',
            'code',
            'id',
          ]);
          final name = stringField(pool, const [
            'bankName',
            'BankName',
            'name',
          ]);
          if (code == null || name == null) return null;
          return ServiceOption(id: code, name: name, meta: 'GIP bank code');
        })
        .whereType<ServiceOption>()
        .toList();
  }

  @override
  Future<ServiceReceipt> payGtPayService({
    required String serviceName,
    required String serviceNumber,
    String? secondaryServiceNumber,
    required double amount,
    required String remarks,
  }) async {
    final payee = await _gtPayPayeeName(serviceName, serviceNumber);
    final raw = await _api.postRaw(
      ApiEndpoints.gtPayPay,
      body: {
        if (_effectiveUserId != null) 'userId': _effectiveUserId,
        if (_effectiveUserName != null) 'userName': _effectiveUserName,
        'ServiceDetails': {
          'ServiceName': serviceName,
          'ServiceNumber': serviceNumber,
          if (secondaryServiceNumber != null &&
              secondaryServiceNumber.isNotEmpty)
            'SecondaryServiceNumber': secondaryServiceNumber,
          // GTBank hashes the body, so the amount travels as an exact string.
          'Amount': amount.toStringAsFixed(2),
          'Remarks': remarks,
          'PaidBy': _effectiveUserName ?? 'Lidapay user',
          'PayeeName': ?payee,
        },
      },
    );
    return _receipt(
      raw,
      title: 'GTPay payment sent',
      amount: amount,
      prefix: 'GTP',
      fallbackMessage: '$serviceName paid for $serviceNumber.',
    );
  }

  /// Verification is advisory: a failed query must not block a payment the
  /// user explicitly asked for, but a successful one names the recipient.
  Future<String?> _gtPayPayeeName(
    String serviceName,
    String serviceNumber,
  ) async {
    try {
      final raw = await _api.postRaw(
        ApiEndpoints.gtPayQuery,
        body: {'ServiceName': serviceName, 'ServiceNumber': serviceNumber},
      );
      return stringField(payloadPool(asMap(raw)), const [
        'CustomerName',
        'customerName',
        'PayeeName',
        'Name',
        'displayName',
      ]);
    } on ApiException {
      return null;
    }
  }

  @override
  Future<ServiceReceipt> payQr({
    required String merchantCode,
    required double amount,
  }) => _unavailable('QR payment');

  @override
  Future<ServiceReceipt> redeemPoints({required int points}) async {
    final quote = await getPointsRedeemQuote(points: points.toDouble());
    return confirmPointsRedeem(
      quoteId: quote.quoteId,
      idempotencyKey: 'LPR-${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  Future<T> _firstRedeemPath<T>(
    List<String> paths,
    Future<T> Function(String path) call,
  ) async {
    ApiException? last;
    for (final path in paths) {
      try {
        return await call(path);
      } on ApiException catch (e) {
        if (e.statusCode == 404) {
          last = e;
          continue;
        }
        rethrow;
      }
    }
    throw last ??
        const ApiException('Points redemption is not available right now.');
  }

  @override
  Future<List<PointsRedeemOption>> getPointsRedeemOptions() =>
      _firstRedeemPath(ApiEndpoints.lidapointsRedeemOptions, (path) async {
        final raw = await _api.getRaw(path);
        return rowsOf(raw)
            .map(PointsRedeemOption.fromJson)
            .where((o) => o.name.isNotEmpty)
            .toList();
      });

  @override
  Future<PointsRedeemQuote> getPointsRedeemQuote({
    required double points,
    String? optionId,
  }) => _firstRedeemPath(ApiEndpoints.lidapointsRedeemQuote, (path) async {
    final raw = await _api.postRaw(
      path,
      body: {
        'points': points,
        if (optionId != null && optionId.isNotEmpty) 'optionId': optionId,
      },
    );
    return PointsRedeemQuote.fromJson(asMap(raw));
  });

  @override
  Future<ServiceReceipt> confirmPointsRedeem({
    required String quoteId,
    String? destination,
    required String idempotencyKey,
  }) => _firstRedeemPath(ApiEndpoints.lidapointsRedeemConfirm, (path) async {
    final raw = await _api.postRaw(
      path,
      body: {
        'quoteId': quoteId,
        if (destination != null && destination.isNotEmpty)
          'destination': destination,
      },
      headers: {'X-Idempotency-Key': idempotencyKey},
    );
    return _receipt(
      raw,
      title: 'Points redeemed',
      amount: 0,
      prefix: 'LPR',
      fallbackMessage: 'Your points were redeemed successfully.',
    );
  });

  Future<List<ServiceReceipt>> _history(String path) async {
    try {
      final raw = await _api.getRaw(
        path,
        queryParameters: const {'limit': 20, 'page': 1},
      );
      return rowsOf(raw)
          .map((row) {
            final pool = payloadPool(row);
            final reference = stringField(pool, _referenceKeys);
            if (reference == null) return null;
            return ServiceReceipt(
              reference: reference,
              title:
                  stringField(pool, const [
                    'type',
                    'transactionType',
                    'title',
                    'action',
                    'category',
                  ]) ??
                  'Activity',
              message:
                  stringField(pool, const [
                    'description',
                    'message',
                    'status',
                    'remarks',
                    'narration',
                  ]) ??
                  '',
              amount:
                  numberField(pool, [
                    if (path == ApiEndpoints.lidapointsHistory) 'points',
                    'amount',
                    'valueUnits',
                    'points',
                    'total',
                  ]) ??
                  0,
              createdAt: _dateOf(pool),
              isCredit: switch (stringField(pool, const [
                'direction',
                'entryType',
              ])?.toLowerCase()) {
                'credit' || 'accrual' => true,
                'debit' || 'redemption' => false,
                _ => null,
              },
            );
          })
          .whereType<ServiceReceipt>()
          .toList();
    } on ApiException {
      return const [];
    }
  }

  ServiceReceipt _receipt(
    Object? raw, {
    required String title,
    required double amount,
    required String prefix,
    required String fallbackMessage,
  }) {
    final pool = payloadPool(asMap(raw));
    return ServiceReceipt(
      pendingTopup: _pendingTopupOf(pool),
      reference:
          stringField(pool, _referenceKeys) ??
          '$prefix-${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      message: _withDecisionNote(
        stringField(pool, const [
              'message',
              'Message',
              'status',
              'Status',
              'description',
              'remarks',
              'responseData',
            ]) ??
            fallbackMessage,
        pool,
      ),
      amount:
          numberField(pool, const [
            'amount',
            'Amount',
            'totalAmount',
            'value',
          ]) ??
          amount,
      createdAt: _dateOf(pool),
    );
  }

  /// The backend parks delivery when a registered recipient must choose
  /// between direct credit and Lida Value. A parked top-up surfaces as
  /// `status: PENDING` together with a `decisionId`/`topupOrderId`.
  static PendingTopup? _pendingTopupOf(Map<String, dynamic> pool) {
    final status =
        (stringField(pool, const ['status', 'Status', 'state']) ?? '')
            .toUpperCase();
    final looksPending = status.contains('PENDING') || status.contains('AWAIT');
    final decisionId = stringField(pool, const [
      'decisionId',
      'decision_id',
      'DecisionId',
    ]);
    final topupOrderId = stringField(pool, const [
      'topupOrderId',
      'topup_order_id',
      'topupId',
      'orderId',
    ]);
    if (!looksPending || (decisionId == null && topupOrderId == null)) {
      return null;
    }
    return PendingTopup(
      topupOrderId: topupOrderId ?? decisionId!,
      decisionId: decisionId,
      expiresAt: dateField(pool, const [
        'expiresAt',
        'decisionExpiresAt',
        'expires_at',
      ]),
    );
  }

  static String _withDecisionNote(String message, Map<String, dynamic> pool) {
    final hasDecision =
        stringField(pool, const ['decisionId', 'decision_id', 'DecisionId']) !=
            null ||
        stringField(pool, const ['topupOrderId', 'topup_order_id']) != null;
    if (!hasDecision) return message;
    final expires = dateField(pool, const [
      'expiresAt',
      'decisionExpiresAt',
      'expires_at',
    ]);
    final note = 'The recipient now chooses delivery or Lida Value';
    return '$message ${expires == null ? '$note.' : '$note before ${Formatters.dateTime(expires.toLocal())}.'}';
  }

  /// Embedded catalogue for pre-auth flows (e.g. registration): the backend
  /// guards `reloadly/country-list` with a bearer token, so a signed-out user
  /// gets 401 and lands here. Covers the common Reloadly top-up destinations;
  /// the live list replaces it once a session exists.
  static List<ServiceOption> _staticCountries() => _sorted([
    ServiceOption(id: 'GH', name: 'Ghana', meta: 'GHS', dialCode: '+233'),
    ServiceOption(id: 'NG', name: 'Nigeria', meta: 'NGN', dialCode: '+234'),
    ServiceOption(id: 'KE', name: 'Kenya', meta: 'KES', dialCode: '+254'),
    ServiceOption(id: 'CI', name: 'Ivory Coast', meta: 'XOF', dialCode: '+225'),
    ServiceOption(id: 'SN', name: 'Senegal', meta: 'XOF', dialCode: '+221'),
    ServiceOption(id: 'CM', name: 'Cameroon', meta: 'XAF', dialCode: '+237'),
    ServiceOption(id: 'BJ', name: 'Benin', meta: 'XOF', dialCode: '+229'),
    ServiceOption(
      id: 'BF',
      name: 'Burkina Faso',
      meta: 'XOF',
      dialCode: '+226',
    ),
    ServiceOption(id: 'TG', name: 'Togo', meta: 'XOF', dialCode: '+228'),
    ServiceOption(id: 'ML', name: 'Mali', meta: 'XOF', dialCode: '+223'),
    ServiceOption(id: 'GN', name: 'Guinea', meta: 'GNF', dialCode: '+224'),
    ServiceOption(id: 'LR', name: 'Liberia', meta: 'LRD', dialCode: '+231'),
    ServiceOption(
      id: 'SL',
      name: 'Sierra Leone',
      meta: 'SLE',
      dialCode: '+232',
    ),
    ServiceOption(id: 'GM', name: 'Gambia', meta: 'GMD', dialCode: '+220'),
    ServiceOption(id: 'RW', name: 'Rwanda', meta: 'RWF', dialCode: '+250'),
    ServiceOption(id: 'UG', name: 'Uganda', meta: 'UGX', dialCode: '+256'),
    ServiceOption(id: 'TZ', name: 'Tanzania', meta: 'TZS', dialCode: '+255'),
    ServiceOption(id: 'MW', name: 'Malawi', meta: 'MWK', dialCode: '+265'),
    ServiceOption(id: 'ZM', name: 'Zambia', meta: 'ZMW', dialCode: '+260'),
    ServiceOption(id: 'ZW', name: 'Zimbabwe', meta: 'ZWG', dialCode: '+263'),
    ServiceOption(id: 'MZ', name: 'Mozambique', meta: 'MZN', dialCode: '+258'),
    ServiceOption(id: 'AO', name: 'Angola', meta: 'AOA', dialCode: '+244'),
    ServiceOption(id: 'ZA', name: 'South Africa', meta: 'ZAR', dialCode: '+27'),
    ServiceOption(id: 'BW', name: 'Botswana', meta: 'BWP', dialCode: '+267'),
    ServiceOption(id: 'NA', name: 'Namibia', meta: 'NAD', dialCode: '+264'),
    ServiceOption(id: 'ET', name: 'Ethiopia', meta: 'ETB', dialCode: '+251'),
    ServiceOption(id: 'CD', name: 'DR Congo', meta: 'CDF', dialCode: '+243'),
    ServiceOption(
      id: 'CG',
      name: 'Congo Republic',
      meta: 'XAF',
      dialCode: '+242',
    ),
    ServiceOption(id: 'GA', name: 'Gabon', meta: 'XAF', dialCode: '+241'),
    ServiceOption(id: 'NE', name: 'Niger', meta: 'XOF', dialCode: '+227'),
    ServiceOption(id: 'TD', name: 'Chad', meta: 'XAF', dialCode: '+235'),
    ServiceOption(id: 'MR', name: 'Mauritania', meta: 'MRU', dialCode: '+222'),
    ServiceOption(id: 'MA', name: 'Morocco', meta: 'MAD', dialCode: '+212'),
    ServiceOption(id: 'DZ', name: 'Algeria', meta: 'DZD', dialCode: '+213'),
    ServiceOption(id: 'TN', name: 'Tunisia', meta: 'TND', dialCode: '+216'),
    ServiceOption(id: 'EG', name: 'Egypt', meta: 'EGP', dialCode: '+20'),
    ServiceOption(id: 'US', name: 'United States', meta: 'USD', dialCode: '+1'),
    ServiceOption(id: 'CA', name: 'Canada', meta: 'CAD', dialCode: '+1'),
    ServiceOption(id: 'MX', name: 'Mexico', meta: 'MXN', dialCode: '+52'),
    ServiceOption(id: 'JM', name: 'Jamaica', meta: 'JMD', dialCode: '+1876'),
    ServiceOption(id: 'HT', name: 'Haiti', meta: 'HTG', dialCode: '+509'),
    ServiceOption(
      id: 'DO',
      name: 'Dominican Republic',
      meta: 'DOP',
      dialCode: '+1809',
    ),
    ServiceOption(
      id: 'GB',
      name: 'United Kingdom',
      meta: 'GBP',
      dialCode: '+44',
    ),
    ServiceOption(id: 'IE', name: 'Ireland', meta: 'EUR', dialCode: '+353'),
    ServiceOption(id: 'FR', name: 'France', meta: 'EUR', dialCode: '+33'),
    ServiceOption(id: 'DE', name: 'Germany', meta: 'EUR', dialCode: '+49'),
    ServiceOption(id: 'NL', name: 'Netherlands', meta: 'EUR', dialCode: '+31'),
    ServiceOption(id: 'ES', name: 'Spain', meta: 'EUR', dialCode: '+34'),
    ServiceOption(id: 'IT', name: 'Italy', meta: 'EUR', dialCode: '+39'),
    ServiceOption(id: 'PT', name: 'Portugal', meta: 'EUR', dialCode: '+351'),
    ServiceOption(id: 'BE', name: 'Belgium', meta: 'EUR', dialCode: '+32'),
    ServiceOption(id: 'CH', name: 'Switzerland', meta: 'CHF', dialCode: '+41'),
    ServiceOption(id: 'SE', name: 'Sweden', meta: 'SEK', dialCode: '+46'),
    ServiceOption(id: 'NO', name: 'Norway', meta: 'NOK', dialCode: '+47'),
    ServiceOption(id: 'DK', name: 'Denmark', meta: 'DKK', dialCode: '+45'),
    ServiceOption(id: 'PL', name: 'Poland', meta: 'PLN', dialCode: '+48'),
    ServiceOption(id: 'TR', name: 'Turkey', meta: 'TRY', dialCode: '+90'),
    ServiceOption(id: 'AE', name: 'UAE', meta: 'AED', dialCode: '+971'),
    ServiceOption(
      id: 'SA',
      name: 'Saudi Arabia',
      meta: 'SAR',
      dialCode: '+966',
    ),
    ServiceOption(id: 'QA', name: 'Qatar', meta: 'QAR', dialCode: '+974'),
    ServiceOption(id: 'KW', name: 'Kuwait', meta: 'KWD', dialCode: '+965'),
    ServiceOption(id: 'IN', name: 'India', meta: 'INR', dialCode: '+91'),
    ServiceOption(id: 'PK', name: 'Pakistan', meta: 'PKR', dialCode: '+92'),
    ServiceOption(id: 'BD', name: 'Bangladesh', meta: 'BDT', dialCode: '+880'),
    ServiceOption(id: 'LK', name: 'Sri Lanka', meta: 'LKR', dialCode: '+94'),
    ServiceOption(id: 'NP', name: 'Nepal', meta: 'NPR', dialCode: '+977'),
    ServiceOption(id: 'PH', name: 'Philippines', meta: 'PHP', dialCode: '+63'),
    ServiceOption(id: 'VN', name: 'Vietnam', meta: 'VND', dialCode: '+84'),
    ServiceOption(id: 'ID', name: 'Indonesia', meta: 'IDR', dialCode: '+62'),
    ServiceOption(id: 'MY', name: 'Malaysia', meta: 'MYR', dialCode: '+60'),
    ServiceOption(id: 'SG', name: 'Singapore', meta: 'SGD', dialCode: '+65'),
    ServiceOption(id: 'TH', name: 'Thailand', meta: 'THB', dialCode: '+66'),
    ServiceOption(id: 'CN', name: 'China', meta: 'CNY', dialCode: '+86'),
    ServiceOption(id: 'AU', name: 'Australia', meta: 'AUD', dialCode: '+61'),
    ServiceOption(id: 'NZ', name: 'New Zealand', meta: 'NZD', dialCode: '+64'),
    ServiceOption(id: 'BR', name: 'Brazil', meta: 'BRL', dialCode: '+55'),
    ServiceOption(id: 'AR', name: 'Argentina', meta: 'ARS', dialCode: '+54'),
    ServiceOption(id: 'CO', name: 'Colombia', meta: 'COP', dialCode: '+57'),
    ServiceOption(id: 'CL', name: 'Chile', meta: 'CLP', dialCode: '+56'),
    ServiceOption(id: 'PE', name: 'Peru', meta: 'PEN', dialCode: '+51'),
    ServiceOption(id: 'EC', name: 'Ecuador', meta: 'USD', dialCode: '+593'),
    ServiceOption(id: 'GT', name: 'Guatemala', meta: 'GTQ', dialCode: '+502'),
    ServiceOption(id: 'HN', name: 'Honduras', meta: 'HNL', dialCode: '+504'),
    ServiceOption(id: 'SV', name: 'El Salvador', meta: 'USD', dialCode: '+503'),
    ServiceOption(id: 'NI', name: 'Nicaragua', meta: 'NIO', dialCode: '+505'),
    ServiceOption(id: 'CR', name: 'Costa Rica', meta: 'CRC', dialCode: '+506'),
    ServiceOption(id: 'PA', name: 'Panama', meta: 'PAB', dialCode: '+507'),
    ServiceOption(id: 'GY', name: 'Guyana', meta: 'GYD', dialCode: '+592'),
    ServiceOption(
      id: 'TT',
      name: 'Trinidad & Tobago',
      meta: 'TTD',
      dialCode: '+1868',
    ),
  ]);

  static const _referenceKeys = [
    'transactionReference',
    'transactionId',
    'TransactionId',
    'transaction_id',
    'transId',
    'TrxnId',
    'trxn',
    'reference',
    'Reference',
    'ref',
    'topupOrderId',
    'orderId',
    'orderNumber',
    'PartnerTransId',
    'partnerTransId',
    'TransId',
    '_id',
    'id',
  ];

  static int _networkCode(String networkId) =>
      int.tryParse(networkId.trim()) ?? 0;

  /// Reloadly expects an international MSISDN. Ghana input such as
  /// `024 123 4567` expands to `233...`; other destinations expand through
  /// the selected country's dial code (e.g. `0803456789` → `234803456789`).
  static String _normalizedMsisdn(
    String input,
    String countryCode, [
    String? dialCode,
  ]) {
    var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (countryCode.toUpperCase() == 'GH') {
      return digits.length == 10 && digits.startsWith('0')
          ? '233${digits.substring(1)}'
          : digits;
    }
    final prefix = (dialCode ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (prefix.isEmpty || digits.startsWith(prefix)) return digits;
    return '$prefix${digits.replaceFirst(RegExp('^0+'), '')}';
  }

  static DateTime _dateOf(Map<String, dynamic> map) =>
      dateField(map, const [
        'createdAt',
        'created_at',
        'date',
        'transactionDate',
        'timestamp',
        'updatedAt',
      ]) ??
      DateTime.now();
}
