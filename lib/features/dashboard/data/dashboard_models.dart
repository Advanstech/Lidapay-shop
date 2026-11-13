import 'package:equatable/equatable.dart';

import '../../shop/data/shop_models.dart';

/// GET /api/v1/users/wallet/user — shape loosely typed in swagger;
/// confirmed against live responses when wiring up.
class WalletSummary extends Equatable {
  const WalletSummary({
    required this.balance,
    required this.currency,
    required this.lidaValueUnits,
    required this.lidaPoints,
    this.walletAvailable = true,
  });

  final double balance;
  final String currency;

  /// Lida Value balance, from GET /api/v1/lida-value/balance
  /// (totalValueUnits in the spec).
  final double lidaValueUnits;
  final int lidaPoints;

  /// False when GET /api/v1/users/wallet/user failed (the live backend
  /// returns 500 for users without a wallet document).
  final bool walletAvailable;

  @override
  List<Object?> get props => [
    balance,
    currency,
    lidaValueUnits,
    lidaPoints,
    walletAvailable,
  ];
}

enum TransactionType {
  airtime,
  data,
  shopOrder,
  lidaValue,
  walletTopUp,
  other;

  String get label => switch (this) {
    TransactionType.airtime => 'Airtime',
    TransactionType.data => 'Data',
    TransactionType.shopOrder => 'Shop Order',
    TransactionType.lidaValue => 'Lida Value',
    TransactionType.walletTopUp => 'Top Up',
    TransactionType.other => 'Other',
  };

  /// Maps a live `transType` string (e.g. "AIRTIME", "MOMO") onto the enum.
  static TransactionType fromApi(String raw) {
    final v = raw.toUpperCase();
    if (v.contains('AIRTIME') || v.contains('RELOAD')) {
      return TransactionType.airtime;
    }
    if (v.contains('DATA')) return TransactionType.data;
    if (v.contains('SHOP') || v.contains('ORDER')) {
      return TransactionType.shopOrder;
    }
    if (v.contains('LIDA')) return TransactionType.lidaValue;
    if (v.contains('TOPUP') || v.contains('TOP_UP') || v.contains('FUND')) {
      return TransactionType.walletTopUp;
    }
    return TransactionType.other;
  }
}

enum TransactionStatus {
  success,
  pending,
  failed;

  static TransactionStatus fromApi(String? raw) {
    final v = (raw ?? '').toUpperCase();
    if (v.contains('SUCCESS') ||
        v.contains('COMPLETED') ||
        v.contains('DELIVERED')) {
      return TransactionStatus.success;
    }
    if (v.contains('FAIL') || v.contains('ERROR') || v.contains('EXPIRED')) {
      return TransactionStatus.failed;
    }
    return TransactionStatus.pending;
  }
}

class Transaction extends Equatable {
  const Transaction({
    required this.id,
    required this.reference,
    required this.type,
    required this.status,
    required this.amount,
    required this.currency,
    required this.createdAt,
    this.counterparty,
    this.description = '',
    this.isCredit,
    this.statusDetail,
    this.isAwaitingRecipientDecision = false,
  });

  final String id;
  final String reference;
  final TransactionType type;
  final TransactionStatus status;
  final double amount;
  final String currency;
  final DateTime createdAt;
  final String? counterparty;
  final String description;

  /// Explicit money-in/money-out direction supplied by the aggregator or a
  /// `direction`/`flow` field in the payload. Falls back to the legacy
  /// heuristic: top-ups and accepted Lida Value are credits.
  final bool? isCredit;

  /// Server-supplied reason for the current status — mainly populated on
  /// failed/pending rows (failedReason, errorMessage, …). Drives the
  /// analytics failure-reason breakdown.
  final String? statusDetail;

  /// True while a top-up is parked behind the recipient's accept/Lida-Value
  /// decision (`status.service == 'decision_pending'` on the ledger). The
  /// dashboard surfaces these as live "waiting" cards until they settle.
  final bool isAwaitingRecipientDecision;

  /// Resolved direction used by every activity row/summary.
  bool get isMoneyIn =>
      isCredit ??
      (type == TransactionType.walletTopUp ||
          (type == TransactionType.lidaValue &&
              description.contains('accepted')));

  /// Tolerant parse of a live transaction row — the NestJS entity is not
  /// annotated in swagger, so every field tries the plausible key spellings.
  factory Transaction.fromApiJson(Map<String, dynamic> json) {
    DateTime? created;
    for (final key in [
      // Live ledger rows from /transactions/user/{id} carry `initiatedAt`
      // (the metadata structure the legacy app was built around).
      'initiatedAt',
      'createdAt',
      'date',
      'timestamp',
      'transDate',
      'updatedAt',
      'created_at',
    ]) {
      created ??= DateTime.tryParse((json[key] ?? '').toString());
      if (created != null) break;
    }
    double? amount;
    // The ledger nests money under `monetary` (old app's live shape) — read
    // it before the flat spellings.
    if (json['monetary'] is Map) {
      final m = json['monetary'] as Map;
      for (final key in ['amount', 'originalAmount', 'value', 'total']) {
        final raw = m[key];
        if (raw is num) amount ??= raw.toDouble();
        if (raw is String) amount ??= double.tryParse(raw);
        if (amount != null) break;
      }
    }
    for (final key in [
      'amount',
      'transAmount',
      'value',
      'totalAmount',
      'chargedAmount',
      'paidAmount',
      'transactionAmount',
      'debitAmount',
    ]) {
      final raw = json[key];
      if (raw is num) amount ??= raw.toDouble();
      if (raw is String) amount ??= double.tryParse(raw);
      if (amount != null) break;
    }
    String? counterparty;
    for (final key in [
      'recipientNumber',
      'recipientPhone',
      'recipient',
      'accountNumber',
      'destination',
      'receiver',
      'sender',
      'msisdn',
    ]) {
      final raw = json[key]?.toString();
      if (raw != null && raw.isNotEmpty) {
        counterparty = raw;
        break;
      }
    }
    String? description;
    for (final key in ['description', 'narrative', 'notes', 'remark']) {
      final raw = json[key]?.toString();
      if (raw != null && raw.isNotEmpty) {
        description = raw;
        break;
      }
    }
    String? statusDetail;
    for (final key in [
      'failedReason',
      'failureReason',
      'statusReason',
      'statusDetail',
      'errorMessage',
      'reason',
      'rejectionReason',
    ]) {
      final raw = json[key]?.toString();
      if (raw != null && raw.isNotEmpty) {
        statusDetail = raw;
        break;
      }
    }
    String? reference;
    for (final key in [
      'transId',
      'trxn',
      'reference',
      'ref',
      'transRef',
      '_id',
      'id',
    ]) {
      final raw = json[key]?.toString();
      if (raw != null && raw.isNotEmpty) {
        reference = raw;
        break;
      }
    }
    bool? isCredit;
    for (final key in [
      'direction',
      'flow',
      'transDirection',
      'entryType',
      'drCr',
    ]) {
      final raw = json[key]?.toString().toUpperCase();
      if (raw == null || raw.isEmpty) continue;
      if (raw.contains('CR') ||
          raw.contains('IN') ||
          raw.contains('CREDIT') ||
          raw.contains('RECEIV')) {
        isCredit = true;
      } else if (raw.contains('DR') ||
          raw.contains('OUT') ||
          raw.contains('DEBIT') ||
          raw.contains('SENT')) {
        isCredit = false;
      }
      if (isCredit != null) break;
    }
    final currency =
        (json['monetary'] is Map
                ? ((json['monetary'] as Map)['currency'] ?? json['currency'])
                : json['currency'] ??
                      'GHS')
            .toString()
            .trim()
            .toUpperCase();
    // `status` arrives either as a string or an object with
    // transaction/service/payment legs (the live ledger shape).
    String? rawStatus;
    var awaitingDecision = false;
    if (json['status'] is Map) {
      final st = json['status'] as Map;
      rawStatus = (st['transaction'] ?? st['service'] ?? st['payment'])
          ?.toString();
      // The ledger splits status into transaction/service/payment legs —
      // a parked recipient decision shows as service='decision_pending'
      // while transaction stays 'pending'.
      awaitingDecision = st.values.any(
        (v) => (v ?? '').toString().toLowerCase().contains('decision'),
      );
    } else {
      rawStatus =
          (json['status'] ??
                  json['result-text'] ??
                  json['resultText'] ??
                  json['result'])
              ?.toString();
    }
    return Transaction(
      id: (json['_id'] ?? json['id'] ?? reference ?? '').toString(),
      reference: reference ?? '',
      type: TransactionType.fromApi(
        (json['transType'] ?? json['type'] ?? json['provider'] ?? '')
            .toString(),
      ),
      status: TransactionStatus.fromApi(rawStatus),
      amount: amount ?? 0,
      currency: currency.isEmpty ? 'GHS' : currency,
      createdAt: created ?? DateTime.now(),
      counterparty: counterparty,
      description: description ?? '',
      isCredit: isCredit,
      statusDetail: statusDetail,
      isAwaitingRecipientDecision: awaitingDecision,
    );
  }

  @override
  List<Object?> get props => [
    id,
    reference,
    type,
    status,
    amount,
    currency,
    createdAt,
    statusDetail,
    isAwaitingRecipientDecision,
  ];
}

/// Time-boxed partner deal surfaced on the dashboard. The countdown must be
/// driven by [endsAt] (server time) — the widget reconciles drift on open.
class FlashDeal extends Equatable {
  const FlashDeal({
    required this.id,
    required this.partnerName,
    required this.title,
    required this.imageUrl,
    required this.originalPrice,
    required this.dealPrice,
    required this.currency,
    required this.endsAt,
    this.productId,
  });

  final String id;
  final String partnerName;
  final String title;
  final String imageUrl;
  final double originalPrice;
  final double dealPrice;
  final String currency;

  /// Server-authoritative expiry. Countdown chips tick from this value.
  final DateTime endsAt;

  /// Deep-link target in the Shop tab.
  final String? productId;

  int get discountPercent =>
      originalPrice <= 0 ? 0 : ((1 - dealPrice / originalPrice) * 100).round();

  /// Converts this deal to a [ShopProduct] so the Shop screen and product detail
  /// sheet can display and transact on it directly.
  ShopProduct toShopProduct() {
    return ShopProduct(
      id: productId ?? id,
      name: title,
      categoryId: 'deals',
      price: dealPrice,
      oldPrice: originalPrice > dealPrice ? originalPrice : null,
      currency: currency,
      imageAsset: imageUrl,
      stock: 25,
      rating: 4.8,
      sold: 140,
      isFeatured: true,
      description: '$partnerName flash deal — limited-time offer on Lidapay.',
    );
  }

  @override
  List<Object?> get props => [id, partnerName, title, dealPrice, endsAt];
}
