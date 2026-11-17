import 'package:equatable/equatable.dart';

import '../../../core/network/api_payload.dart';

class ServiceOption extends Equatable {
  const ServiceOption({
    required this.id,
    required this.name,
    this.meta,
    this.dialCode,
    this.flagUrl,
    this.bundles = const [],
  });

  final String id;
  final String name;
  final String? meta;
  final String? dialCode;

  /// Country flag image URL (e.g. `https://cdn.reloadly.com/flags/gh.svg`).
  final String? flagUrl;

  /// Fixed-price plans carried on Reloadly data operators
  /// (`fixedAmounts`/`localFixedAmounts` + their description maps).
  final List<DataBundle> bundles;

  @override
  List<Object?> get props => [id, name, meta, dialCode, flagUrl, bundles];
}

/// Result of a Reloadly operator lookup
/// (`POST /api/v1/reloadly/operator/autodetect` for airtime,
/// `GET /api/v1/reloadly-data/auto-detect` for data). Drives the amount step:
/// quick amounts come from [suggestedAmounts], the field validates
/// [minAmount]..[maxAmount], and [fxRate]/[fxCurrencyCode] show the sender
/// what they will actually be charged.
class DetectedOperator extends Equatable {
  const DetectedOperator({
    required this.id,
    required this.name,
    this.minAmount,
    this.maxAmount,
    this.suggestedAmounts = const [],
    this.senderCurrencyCode,
    this.senderCurrencySymbol,
    this.destinationCurrencyCode,
    this.fxRate,
    this.fxCurrencyCode,
    this.logoUrl,
  });

  final int id;
  final String name;
  final double? minAmount;
  final double? maxAmount;
  final List<double> suggestedAmounts;

  /// Currency the sender is charged in — Reloadly prices international
  /// top-ups in the sender currency, normally USD.
  final String? senderCurrencyCode;
  final String? senderCurrencySymbol;

  /// Currency the recipient's top-up is denominated in.
  final String? destinationCurrencyCode;

  /// Sender→destination conversion reported by Reloadly (`fx.rate`,
  /// `localMinAmount/minAmount`, or the `…/operators/{id}/fx-rate` route):
  /// one sender-currency unit buys [fxRate] of [fxCurrencyCode].
  final double? fxRate;
  final String? fxCurrencyCode;

  final String? logoUrl;

  /// Local-currency equivalent of a sender [destinationAmount] (matching the
  /// legacy `amount * fxRate` behaviour), when Reloadly reported a rate.
  double? paymentAmount(double destinationAmount) =>
      fxRate == null ? null : destinationAmount * fxRate!;

  /// Quick-amount chips: API suggestions first, else a spread across the
  /// operator's min…max range.
  List<double> quickAmounts() {
    if (suggestedAmounts.isNotEmpty) return suggestedAmounts;
    final min = minAmount, max = maxAmount;
    if (min == null || max == null || max <= min) return const [];
    if (min < 10) {
      return const [
        1,
        5,
        10,
        15,
        20,
        25,
        30,
        40,
        50,
        75,
        100,
      ].map((a) => a.toDouble()).where((a) => a >= min && a <= max).toList();
    }
    final step = (max - min) / 8;
    return {for (var i = 0; i <= 8; i++) (min + step * i).roundToDouble()}
        .toList()
      ..sort();
  }

  bool accepts(double amount) {
    if (minAmount != null && amount < minAmount!) return false;
    if (maxAmount != null && amount > maxAmount!) return false;
    return true;
  }

  String? get rangeLabel {
    if (minAmount == null || maxAmount == null) return null;
    final symbol = senderCurrencySymbol ?? senderCurrencyCode ?? '';
    return 'Min: $symbol${minAmount!.toStringAsFixed(0)} • '
        'Max: $symbol${maxAmount!.toStringAsFixed(0)}';
  }

  @override
  List<Object?> get props => [id, name];
}

class DataBundle extends Equatable {
  const DataBundle({
    required this.id,
    required this.name,
    required this.price,
    required this.dataAmount,
    this.currency = 'GHS',
  });

  final String id;
  final String name;
  final double price;
  final String dataAmount;

  /// ISO code the price is denominated in — Prymo bundles bill GHS;
  /// Reloadly fixed plans carry the operator's sender/destination code.
  final String currency;

  @override
  List<Object?> get props => [id, name, price, dataAmount, currency];
}

/// A top-up whose delivery is parked behind the recipient's choice: the
/// backend returns `PENDING` plus a `decisionId`/`topupOrderId` when a
/// registered recipient must pick direct delivery or Lida Value. Carried on
/// the receipt so the wizard can swap to the waiting screen instead of
/// showing a fake "sent" confirmation.
class PendingTopup extends Equatable {
  const PendingTopup({
    required this.topupOrderId,
    this.decisionId,
    this.expiresAt,
  });

  final String topupOrderId;
  final String? decisionId;
  final DateTime? expiresAt;

  @override
  List<Object?> get props => [topupOrderId, decisionId, expiresAt];
}

class ServiceReceipt extends Equatable {
  const ServiceReceipt({
    required this.reference,
    required this.title,
    required this.message,
    required this.amount,
    required this.createdAt,
    this.isCredit,
    this.pendingTopup,
    this.recipientNumber,
    this.networkName,
    this.bundleName,
    this.currency,
    this.serviceType,
  });

  final String reference;
  final String title;
  final String message;
  final double amount;
  final DateTime createdAt;
  final bool? isCredit;
  final String? recipientNumber;
  final String? networkName;
  final String? bundleName;
  final String? currency;
  final String? serviceType;

  /// Non-null when the backend parked delivery behind a recipient decision —
  /// poll `GET /topups/{topupOrderId}/status` for the final disposition.
  final PendingTopup? pendingTopup;

  @override
  List<Object?> get props => [
    reference,
    title,
    message,
    amount,
    createdAt,
    isCredit,
    pendingTopup,
    recipientNumber,
    networkName,
    bundleName,
    currency,
    serviceType,
  ];
}

class LidaValueWallet extends Equatable {
  const LidaValueWallet({
    required this.balance,
    required this.pending,
    required this.history,
  });

  final double balance;
  final double pending;
  final List<ServiceReceipt> history;

  @override
  List<Object?> get props => [balance, pending, history];
}

class LidaPointsWallet extends Equatable {
  const LidaPointsWallet({
    required this.balance,
    required this.redeemableValue,
    required this.history,
  });

  final int balance;
  final double redeemableValue;
  final List<ServiceReceipt> history;

  @override
  List<Object?> get props => [balance, redeemableValue, history];
}

/// A redemption destination returned by GET /lidapoints/redeem/options —
/// e.g. cash to MoMo, airtime, data, or Lida Value credit.
class PointsRedeemOption extends Equatable {
  const PointsRedeemOption({
    required this.id,
    required this.name,
    this.description = '',
    this.minPoints = 0,
    this.needsDestination = false,
  });

  final String id;
  final String name;
  final String description;
  final int minPoints;
  final bool needsDestination;

  factory PointsRedeemOption.fromJson(Map<String, dynamic> json) {
    final pool = payloadPool(json);
    final name =
        stringField(pool, const ['name', 'label', 'title', 'option']) ?? '';
    return PointsRedeemOption(
      id:
          stringField(pool, const ['optionId', 'id', 'key', 'type']) ??
          name.toLowerCase().replaceAll(' ', '_'),
      name: name.isEmpty ? 'Redeem' : name,
      description:
          stringField(pool, const [
            'description',
            'subtitle',
            'details',
          ]) ??
          '',
      minPoints:
          numberField(pool, const [
            'minPoints',
            'minimumPoints',
            'minimum',
          ])?.round() ??
          0,
      needsDestination:
          boolField(pool, const ['needsDestination', 'requiresDestination']) ||
          stringField(pool, const ['destinationType', 'payout']) != null,
    );
  }

  @override
  List<Object?> get props => [id];
}

/// POST /lidapoints/redeem/quote result — confirm carries its quoteId.
class PointsRedeemQuote extends Equatable {
  const PointsRedeemQuote({
    required this.quoteId,
    required this.points,
    required this.cashValue,
    required this.currency,
    this.message = '',
  });

  final String quoteId;
  final double points;
  final double cashValue;
  final String currency;
  final String message;

  factory PointsRedeemQuote.fromJson(Map<String, dynamic> json) {
    final pool = payloadPool(json);
    return PointsRedeemQuote(
      quoteId:
          stringField(pool, const ['quoteId', 'quote_id', 'id', 'reference']) ??
          '',
      points: numberField(pool, const ['points', 'amount']) ?? 0,
      cashValue:
          numberField(pool, const [
            'cashValue',
            'value',
            'payoutAmount',
            'amountCedis',
          ]) ??
          0,
      currency:
          stringField(pool, const ['currency', 'currencyCode']) ?? 'GHS',
      message:
          stringField(pool, const ['message', 'description', 'narration']) ??
          '',
    );
  }

  @override
  List<Object?> get props => [quoteId, points];
}

class AffiliateSummary extends Equatable {
  const AffiliateSummary({
    required this.code,
    required this.totalInvites,
    required this.activeUsers,
    required this.earnings,
  });

  final String code;
  final int totalInvites;
  final int activeUsers;
  final double earnings;

  @override
  List<Object?> get props => [code, totalInvites, activeUsers, earnings];
}
