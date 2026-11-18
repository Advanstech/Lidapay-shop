import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_payload.dart';
import 'payment_models.dart';

/// Unique, per-attempt idempotency reference sent to the backend so a
/// retried top-up is deduplicated instead of crediting the user twice.
final _uuid = Uuid();
String newClientReference() => 'LDP-${_uuid.v4()}';

/// What a verified payment should deliver. The credit params for each kind
/// mirror the ServicesRepository call arguments — the payment session
/// rehydrates them from storage so a purchase can complete even after the
/// process was killed while the user was in the checkout browser.
enum PendingPaymentKind {
  ghanaAirtime,
  globalAirtime,
  ghanaData,
  globalData,
  shopOrder,
}

/// Durable pending-purchase record persisted in SharedPreferences the moment
/// initiation succeeds (before the checkout URL opens). [token] is the
/// payment-verification authority; [reference] is the client-generated
/// payTransRef sent at initiation so the callback can be matched.
class PendingPayment extends Equatable {
  const PendingPayment({
    required this.kind,
    required this.reference,
    required this.clientReference,
    required this.payAmount,
    required this.payCurrency,
    required this.deliverAmount,
    required this.deliverCurrency,
    required this.orderDesc,
    required this.params,
    required this.createdAt,
    this.token,
    this.advansisOrderId,
    this.checkoutUrl,
    this.method = PaymentMethod.card,
    this.partnerTransId,
    this.momoNumber,
  });

  final PendingPaymentKind kind;

  /// Client-side reference (`LDP-…`) sent as `payTransRef` at initiation.
  final String reference;

  /// Unique, per-attempt idempotency reference sent to the backend so a
  /// retried top-up is deduplicated instead of crediting the user twice.
  final String clientReference;

  /// What the sender is charged, in [payCurrency] (normally GHS).
  final double payAmount;
  final String payCurrency;

  /// What the recipient receives, in [deliverCurrency] (sender/operator
  /// currency for Reloadly, GHS for Ghana).
  final double deliverAmount;
  final String deliverCurrency;

  final String orderDesc;

  /// Kind-specific credit arguments — see `creditParams` constructors below.
  final Map<String, dynamic> params;

  final DateTime createdAt;
  final String? token;
  final String? advansisOrderId;

  /// Persisted so the checkout page can be reopened if the user returns
  /// before finishing the mobile-money prompt.
  final String? checkoutUrl;

  /// Rail used for this attempt — GTPay MoMo debit or Advansis card checkout.
  final PaymentMethod method;

  /// GTPay reference, generated once per attempt and persisted before the
  /// pay call so status checks always use the same ID.
  final String? partnerTransId;

  /// MoMo wallet GTPay is debiting (shown on the approval screen).
  final String? momoNumber;

  // ---- Kind-specific constructors ----------------------------------------

  factory PendingPayment.ghanaAirtime({
    required String reference,
    required String clientReference,
    required double amount,
    required String recipientNumber,
    required String networkId,
    required bool saveToLidaValue,
    required bool isSelfTopup,
    required String orderDesc,
  }) => PendingPayment(
    kind: PendingPaymentKind.ghanaAirtime,
    reference: reference,
    clientReference: clientReference,
    payAmount: amount,
    payCurrency: 'GHS',
    deliverAmount: amount,
    deliverCurrency: 'GHS',
    orderDesc: orderDesc,
    createdAt: DateTime.now(),
    params: {
      'recipientNumber': recipientNumber,
      'amount': amount,
      'networkId': networkId,
      'saveToLidaValue': saveToLidaValue,
      'isSelfTopup': isSelfTopup,
    },
  );

  factory PendingPayment.globalAirtime({
    required String reference,
    required String clientReference,
    required double payAmount,
    required String payCurrency,
    required double deliverAmount,
    required String deliverCurrency,
    required String recipientNumber,
    required String countryCode,
    String? operatorId,
    String? recipientDialCode,
    String? recipientEmail,
    String? senderNumber,
    String senderCountryCode = 'GH',
    bool isSelfTopup = false,
    required String orderDesc,
  }) => PendingPayment(
    kind: PendingPaymentKind.globalAirtime,
    reference: reference,
    clientReference: clientReference,
    payAmount: payAmount,
    payCurrency: payCurrency,
    deliverAmount: deliverAmount,
    deliverCurrency: deliverCurrency,
    orderDesc: orderDesc,
    createdAt: DateTime.now(),
    params: {
      'recipientNumber': recipientNumber,
      'amount': deliverAmount,
      'countryCode': countryCode,
      'currency': deliverCurrency,
      'isSelfTopup': isSelfTopup,
      if (operatorId != null) 'operatorId': operatorId,
      if (recipientDialCode != null) 'recipientDialCode': recipientDialCode,
      if (recipientEmail != null) 'recipientEmail': recipientEmail,
      if (senderNumber != null) 'senderNumber': senderNumber,
      'senderCountryCode': senderCountryCode,
    },
  );

  factory PendingPayment.ghanaData({
    required String reference,
    required String clientReference,
    required double amount,
    required String recipientNumber,
    required String networkId,
    required String bundleId,
    required String bundleName,
    required String bundleDataAmount,
    required bool saveToLidaValue,
    required bool isSelfTopup,
    required String orderDesc,
  }) => PendingPayment(
    kind: PendingPaymentKind.ghanaData,
    reference: reference,
    clientReference: clientReference,
    payAmount: amount,
    payCurrency: 'GHS',
    deliverAmount: amount,
    deliverCurrency: 'GHS',
    orderDesc: orderDesc,
    createdAt: DateTime.now(),
    params: {
      'recipientNumber': recipientNumber,
      'networkId': networkId,
      'amount': amount,
      'bundle': {
        'id': bundleId,
        'name': bundleName,
        'price': amount,
        'dataAmount': bundleDataAmount,
      },
      'saveToLidaValue': saveToLidaValue,
      'isSelfTopup': isSelfTopup,
    },
  );

  factory PendingPayment.globalData({
    required String reference,
    required String clientReference,
    required double payAmount,
    required String payCurrency,
    required double deliverAmount,
    required String deliverCurrency,
    required String recipientNumber,
    required String countryCode,
    String? operatorId,
    String? operatorName,
    String? recipientDialCode,
    String? recipientEmail,
    String? senderNumber,
    String senderCountryCode = 'GH',
    bool isSelfTopup = false,
    required String orderDesc,
  }) => PendingPayment(
    kind: PendingPaymentKind.globalData,
    reference: reference,
    clientReference: clientReference,
    payAmount: payAmount,
    payCurrency: payCurrency,
    deliverAmount: deliverAmount,
    deliverCurrency: deliverCurrency,
    orderDesc: orderDesc,
    createdAt: DateTime.now(),
    params: {
      'recipientNumber': recipientNumber,
      'amount': deliverAmount,
      'countryCode': countryCode,
      'currency': deliverCurrency,
      'isSelfTopup': isSelfTopup,
      if (operatorId != null) 'operatorId': operatorId,
      if (operatorName != null) 'operatorName': operatorName,
      if (recipientDialCode != null) 'recipientDialCode': recipientDialCode,
      if (recipientEmail != null) 'recipientEmail': recipientEmail,
      if (senderNumber != null) 'senderNumber': senderNumber,
      'senderCountryCode': senderCountryCode,
    },
  );

  factory PendingPayment.shopOrder({
    required String reference,
    required String clientReference,
    required String orderId,
    required String orderNumber,
    required double total,
    required String currency,
  }) => PendingPayment(
    kind: PendingPaymentKind.shopOrder,
    reference: reference,
    clientReference: clientReference,
    payAmount: total,
    payCurrency: currency,
    deliverAmount: total,
    deliverCurrency: currency,
    orderDesc: 'Lidapay shop order $orderNumber',
    createdAt: DateTime.now(),
    params: {'orderId': orderId, 'orderNumber': orderNumber},
  );

  PendingPayment copyWith({
    String? token,
    String? advansisOrderId,
    String? checkoutUrl,
    PaymentMethod? method,
    String? partnerTransId,
    String? momoNumber,
    String? clientReference,
  }) => PendingPayment(
    kind: kind,
    reference: reference,
    clientReference: clientReference ?? this.clientReference,
    payAmount: payAmount,
    payCurrency: payCurrency,
    deliverAmount: deliverAmount,
    deliverCurrency: deliverCurrency,
    orderDesc: orderDesc,
    params: params,
    createdAt: createdAt,
    token: token ?? this.token,
    advansisOrderId: advansisOrderId ?? this.advansisOrderId,
    checkoutUrl: checkoutUrl ?? this.checkoutUrl,
    method: method ?? this.method,
    partnerTransId: partnerTransId ?? this.partnerTransId,
    momoNumber: momoNumber ?? this.momoNumber,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'reference': reference,
    'clientReference': clientReference,
    'payAmount': payAmount,
    'payCurrency': payCurrency,
    'deliverAmount': deliverAmount,
    'deliverCurrency': deliverCurrency,
    'orderDesc': orderDesc,
    'params': params,
    'createdAt': createdAt.toIso8601String(),
    if (token != null) 'token': token,
    if (advansisOrderId != null) 'advansisOrderId': advansisOrderId,
    if (checkoutUrl != null) 'checkoutUrl': checkoutUrl,
    'method': method.name,
    if (partnerTransId != null) 'partnerTransId': partnerTransId,
    if (momoNumber != null) 'momoNumber': momoNumber,
  };

  factory PendingPayment.fromJson(Map<String, dynamic> json) {
    final kindName = stringField(json, const ['kind']) ?? '';
    return PendingPayment(
      kind:
          PendingPaymentKind.values.asNameMap()[kindName] ??
          PendingPaymentKind.ghanaAirtime,
      reference: stringField(json, const ['reference']) ?? '',
      clientReference: stringField(json, const ['clientReference']) ?? '',
      payAmount: numberField(json, const ['payAmount']) ?? 0,
      payCurrency: stringField(json, const ['payCurrency']) ?? 'GHS',
      deliverAmount: numberField(json, const ['deliverAmount']) ?? 0,
      deliverCurrency: stringField(json, const ['deliverCurrency']) ?? 'GHS',
      orderDesc: stringField(json, const ['orderDesc']) ?? '',
      params: asMap(json['params']),
      createdAt: dateField(json, const ['createdAt']) ?? DateTime.now(),
      token: stringField(json, const ['token']),
      advansisOrderId: stringField(json, const ['advansisOrderId']),
      checkoutUrl: stringField(json, const ['checkoutUrl']),
      method:
          PaymentMethod.values.asNameMap()[stringField(json, const [
            'method',
          ])] ??
          PaymentMethod.card,
      partnerTransId: stringField(json, const ['partnerTransId']),
      momoNumber: stringField(json, const ['momoNumber']),
    );
  }

  @override
  List<Object?> get props => [kind, reference, clientReference];
}
