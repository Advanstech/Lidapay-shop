import 'package:equatable/equatable.dart';

import '../../../core/network/api_payload.dart';

/// Parsed `data` from POST /api/v1/advansispay/initiate-payment.
/// The [token] is the only authority for later verification — the
/// `orderId` and the deep-link callback's `status` are hints.
class PaymentInitiation extends Equatable {
  const PaymentInitiation({
    required this.checkoutUrl,
    required this.token,
    required this.orderId,
  });

  final String checkoutUrl;
  final String token;
  final String orderId;

  factory PaymentInitiation.fromJson(Map<String, dynamic> json) {
    final pool = payloadPool(json);
    return PaymentInitiation(
      checkoutUrl:
          stringField(pool, const [
            'checkoutUrl',
            'checkout_url',
            'paymentUrl',
            'payment_url',
            'url',
          ]) ??
          '',
      token:
          stringField(pool, const ['token', 'paymentToken', 'payment_token']) ??
          '',
      orderId:
          stringField(pool, const [
            'order-id',
            'orderId',
            'order_id',
            'orderRef',
          ]) ??
          '',
    );
  }

  bool get isUsable => checkoutUrl.isNotEmpty && token.isNotEmpty;

  @override
  List<Object?> get props => [checkoutUrl, token, orderId];
}

/// Coarse classification of a query-transaction payload. The gateway's own
/// status vocabulary is inconsistent, so both `status` and the provider's
/// `resultText`/`originalResponse.result` are consulted — mirroring the
/// released app's verification rules.
enum PaymentOutcome { success, failed, pending }

/// Parsed `data` from POST /api/v1/advansispay/query-transaction.
class PaymentQueryResult extends Equatable {
  const PaymentQueryResult({
    this.orderId,
    this.transactionId,
    this.status,
    this.resultText,
    this.originalResultText,
    this.originalResult,
    this.amount,
    this.currency,
  });

  final String? orderId;
  final String? transactionId;
  final String? status;
  final String? resultText;
  final String? originalResultText;
  final int? originalResult;
  final double? amount;
  final String? currency;

  factory PaymentQueryResult.fromJson(Map<String, dynamic> json) {
    final pool = payloadPool(json);
    // The provider's raw response arrives under `originalResponse` /
    // `original_response` with kebab-case keys.
    final original = asMap(
      pool['originalResponse'] ?? pool['original_response'] ?? pool['original'],
    );
    return PaymentQueryResult(
      orderId: stringField(pool, const ['orderId', 'order-id', 'order_id']),
      transactionId: stringField(pool, const [
        'transactionId',
        'transaction-id',
        'transaction_id',
      ]),
      status: stringField(pool, const ['status', 'paymentStatus']),
      resultText: stringField(pool, const ['resultText', 'result-text']),
      originalResultText: stringField(original, const [
        'result-text',
        'resultText',
      ]),
      originalResult: numberField(original, const ['result'])?.round(),
      amount: numberField(pool, const ['amount']),
      currency: stringField(pool, const ['currency', 'currencyCode']),
    );
  }

  static const _successStatuses = {
    'COMPLETED',
    'APPROVED',
    'SUCCESS',
    'SUCCESSFUL',
    'PAID',
  };
  static const _failureStatuses = {
    'FAILED',
    'FAILURE',
    'CANCELLED',
    'CANCELED',
    'DECLINED',
    'EXPIRED',
    'REVERSED',
    'ERROR',
  };

  static bool _hasSuccessText(String? text) {
    final lower = text?.toLowerCase() ?? '';
    return lower.contains('success') && !lower.contains('unsuccess');
  }

  PaymentOutcome get outcome {
    final statusUpper = status?.toUpperCase() ?? '';
    if (_successStatuses.contains(statusUpper) ||
        _hasSuccessText(resultText) ||
        _hasSuccessText(originalResultText) ||
        originalResult == 1) {
      return PaymentOutcome.success;
    }
    final resultLower = resultText?.toLowerCase() ?? '';
    final originalLower = originalResultText?.toLowerCase() ?? '';
    if (_failureStatuses.contains(statusUpper) ||
        resultLower.contains('fail') ||
        resultLower.contains('error') ||
        originalLower.contains('fail') ||
        originalLower.contains('error')) {
      return PaymentOutcome.failed;
    }
    return PaymentOutcome.pending;
  }

  @override
  List<Object?> get props => [orderId, transactionId, status];
}

/// How the customer pays for a checkout.
/// [mobileMoney] debits their MoMo wallet through GTPay (`debitwallet`);
/// [card] opens the Advansis Pay / ExpressPay hosted checkout.
enum PaymentMethod {
  mobileMoney,
  card;

  String get label => switch (this) {
    PaymentMethod.mobileMoney => 'Mobile Money',
    PaymentMethod.card => 'Debit / Credit Card',
  };
}

/// Parsed `data` from POST /api/v1/gtpay/pay and /api/v1/gtpay/status.
/// The provider state is `data.Status` (PENDING/COMPLETED/FAILED) — never
/// the envelope's HTTP-like `status` number.
class GtPayResult extends Equatable {
  const GtPayResult({
    required this.status,
    this.partnerTransId,
    this.gtbTransId,
    this.message,
    this.network,
    this.charge,
    this.totalAmount,
  });

  final String status;
  final String? partnerTransId;
  final String? gtbTransId;
  final String? message;
  final String? network;
  final double? charge;
  final double? totalAmount;

  factory GtPayResult.fromJson(Map<String, dynamic> json) {
    final inner = json['data'] is Map ? asMap(json['data']) : json;
    final extra = asMap(inner['Data']);
    return GtPayResult(
      status: (stringField(inner, const ['Status', 'status']) ?? 'PENDING')
          .toUpperCase(),
      partnerTransId: stringField(inner, const [
        'PartnerTransId',
        'partnerTransId',
      ]),
      gtbTransId: stringField(inner, const ['GTBTransId', 'gtbTransId']),
      message: stringField(inner, const ['Message', 'message']),
      network: stringField(extra, const ['Network', 'network']),
      charge: numberField(extra, const ['Charge', 'charge']),
      totalAmount: numberField(extra, const ['TotalAmount', 'totalAmount']),
    );
  }

  PaymentOutcome get outcome => switch (status) {
    'COMPLETED' || 'SUCCESS' || 'SUCCESSFUL' => PaymentOutcome.success,
    'FAILED' || 'DECLINED' || 'CANCELLED' || 'CANCELED' || 'REVERSED' =>
      PaymentOutcome.failed,
    _ => PaymentOutcome.pending,
  };

  @override
  List<Object?> get props => [status, partnerTransId, gtbTransId];
}
