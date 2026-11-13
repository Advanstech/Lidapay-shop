import 'package:equatable/equatable.dart';

import '../../../core/network/api_payload.dart';

/// The recipient's answer to "deliver directly or save to Lida Value".
enum RecipientChoice {
  direct('DIRECT'),
  lidaValue('LIDA_VALUE');

  const RecipientChoice(this.apiValue);
  final String apiValue;

  static RecipientChoice? fromApi(String? value) =>
      switch (value?.toUpperCase()) {
        'DIRECT' => RecipientChoice.direct,
        'LIDA_VALUE' => RecipientChoice.lidaValue,
        _ => null,
      };
}

/// Result of `POST /recipient/eligibility` — whether the destination number
/// belongs to a registered user who can pick a delivery method. An unregistered
/// recipient always gets direct delivery, so this only decorates the UI.
class RecipientEligibility extends Equatable {
  const RecipientEligibility({
    required this.isRegistered,
    required this.canPromptChoice,
    required this.defaultChoice,
    required this.timeoutSeconds,
  });

  const RecipientEligibility.unregistered()
    : isRegistered = false,
      canPromptChoice = false,
      defaultChoice = RecipientChoice.lidaValue,
      timeoutSeconds = 180;

  final bool isRegistered;
  final bool canPromptChoice;
  final RecipientChoice defaultChoice;
  final int timeoutSeconds;

  bool get willPromptRecipient => isRegistered && canPromptChoice;

  factory RecipientEligibility.fromJson(Map<String, dynamic> json) {
    final pool = payloadPool(json);
    return RecipientEligibility(
      isRegistered: boolField(pool, const ['isRegistered', 'registered']),
      canPromptChoice: boolField(pool, const [
        'canPromptChoice',
        'promptChoice',
        'eligible',
      ]),
      defaultChoice:
          RecipientChoice.fromApi(
            stringField(pool, const ['defaultChoice', 'fallbackChoice']),
          ) ??
          RecipientChoice.lidaValue,
      timeoutSeconds:
          numberField(pool, const [
            'timeoutSeconds',
            'expiresInSeconds',
            'decisionTimeoutSeconds',
          ])?.round() ??
          180,
    );
  }

  @override
  List<Object?> get props => [
    isRegistered,
    canPromptChoice,
    defaultChoice,
    timeoutSeconds,
  ];
}

/// Decision lifecycle as returned by `GET /recipient-decisions/{id}` and the
/// `decision` snapshot inside `GET /topups/{id}/status`.
enum DecisionStatus {
  pending,
  resolved,
  expired,
  unknown;

  static DecisionStatus fromApi(String? value) => switch (value
      ?.toUpperCase()) {
    'PENDING' => pending,
    'RESOLVED' || 'ACCEPT_DIRECT' || 'SAVE_TO_LIDA' || 'COMPLETED' => resolved,
    'EXPIRED' || 'TIMED_OUT' => expired,
    'REJECT' || 'REJECTED' => expired,
    _ => unknown,
  };
}

class RecipientDecision extends Equatable {
  const RecipientDecision({
    required this.decisionId,
    required this.topupOrderId,
    required this.status,
    this.serviceType,
    this.recipientPhone,
    this.senderName,
    this.amount,
    this.currency,
    this.selectedChoice,
    this.resolvedSource,
    this.finalDisposition,
    this.expiresAt,
    this.respondedAt,
  });

  final String decisionId;
  final String topupOrderId;
  final DecisionStatus status;
  final String? serviceType;
  final String? recipientPhone;
  final String? senderName;
  final double? amount;
  final String? currency;
  final RecipientChoice? selectedChoice;

  /// `RECIPIENT` when the user chose, `TIMEOUT` when the backend applied the
  /// default after the window closed.
  final String? resolvedSource;

  /// `DELIVERED_DIRECT` | `SAVED_TO_LIDA_VALUE` | `DELIVERY_FAILED`.
  final String? finalDisposition;
  final DateTime? expiresAt;
  final DateTime? respondedAt;

  bool get isPending => status == DecisionStatus.pending;
  bool get isResolved => status == DecisionStatus.resolved;
  bool get savedToLidaValue => finalDisposition == 'SAVED_TO_LIDA_VALUE';
  bool get deliveredDirect => finalDisposition == 'DELIVERED_DIRECT';
  bool get deliveryFailed => finalDisposition == 'DELIVERY_FAILED';

  String get serviceLabel =>
      (serviceType ?? '').toUpperCase().contains('DATA') ? 'data' : 'airtime';

  factory RecipientDecision.fromJson(Map<String, dynamic> json) {
    final pool = payloadPool(json);
    return RecipientDecision(
      decisionId:
          stringField(pool, const ['decisionId', 'decision_id', 'id']) ?? '',
      topupOrderId:
          stringField(pool, const [
            'topupOrderId',
            'topup_order_id',
            'transactionRef',
            'transactionReference',
          ]) ??
          '',
      status: DecisionStatus.fromApi(
        stringField(pool, const ['status', 'state', 'decisionStatus']),
      ),
      serviceType: stringField(pool, const ['serviceType', 'service']),
      recipientPhone: stringField(pool, const [
        'recipientPhone',
        'recipient',
        'recipientNumber',
      ]),
      senderName: stringField(pool, const [
        'senderName',
        'sender',
        'senderUsername',
      ]),
      amount: numberField(pool, const [
        'amountOrValueUnits',
        'amount',
        'value',
      ]),
      currency: stringField(pool, const ['currency', 'currencyCode']),
      selectedChoice: RecipientChoice.fromApi(
        stringField(pool, const ['selectedChoice', 'choice', 'decision']),
      ),
      resolvedSource: stringField(pool, const [
        'resolvedSource',
        'resolutionSource',
        'source',
      ]),
      finalDisposition: stringField(pool, const [
        'finalDisposition',
        'disposition',
      ]),
      expiresAt: dateField(pool, const ['expiresAt', 'expires_at']),
      respondedAt: dateField(pool, const [
        'respondedAt',
        'responded_at',
        'decidedAt',
      ]),
    );
  }

  @override
  List<Object?> get props => [
    decisionId,
    topupOrderId,
    status,
    selectedChoice,
    finalDisposition,
    expiresAt,
  ];
}

/// Canonical top-up order state from `GET /topups/{topupOrderId}/status` —
/// the sender and the recipient both poll this to learn where delivery ended.
enum TopupState {
  pending,
  awaitingDecision,
  deliveredDirect,
  deliveredLidaValue,
  failed,
  unknown;

  static TopupState fromApi(String? value) => switch (value?.toUpperCase()) {
    'DELIVERED_DIRECT' => deliveredDirect,
    'DELIVERED_LIDA_VALUE' => deliveredLidaValue,
    'FAILED' || 'DELIVERY_FAILED' || 'REJECTED' => failed,
    'AWAITING_DECISION' || 'AWAITING_RECIPIENT' => awaitingDecision,
    'PENDING' || 'PROCESSING' => pending,
    _ => unknown,
  };
}

class TopupOrderStatus extends Equatable {
  const TopupOrderStatus({
    required this.topupOrderId,
    required this.state,
    this.transactionRef,
    this.finalDisposition,
    this.serviceType,
    this.amount,
    this.recipientPhone,
    this.resolvedAt,
    this.failedReason,
    this.decision,
  });

  final String topupOrderId;
  final TopupState state;
  final String? transactionRef;
  final String? finalDisposition;
  final String? serviceType;
  final double? amount;
  final String? recipientPhone;
  final DateTime? resolvedAt;
  final String? failedReason;
  final RecipientDecision? decision;

  bool get isDeliveredDirect => state == TopupState.deliveredDirect;
  bool get isDeliveredToLidaValue => state == TopupState.deliveredLidaValue;
  bool get isFailed => state == TopupState.failed;
  bool get isTerminal =>
      isDeliveredDirect || isDeliveredToLidaValue || isFailed;
  bool get isWaitingOnRecipient =>
      state == TopupState.awaitingDecision ||
      (state == TopupState.pending && decision?.isPending == true);

  String get serviceLabel =>
      (serviceType ?? '').toUpperCase().contains('DATA') ? 'data' : 'airtime';

  factory TopupOrderStatus.fromJson(Map<String, dynamic> json) {
    final pool = payloadPool(json);
    final disposition = stringField(pool, const [
      'finalDisposition',
      'disposition',
    ]);
    final decisionPool = pool['decision'] is Map
        ? Map<String, dynamic>.from(pool['decision'] as Map)
        : null;
    return TopupOrderStatus(
      topupOrderId:
          stringField(pool, const [
            'topupOrderId',
            'topup_order_id',
            'transactionRef',
            'transactionReference',
          ]) ??
          '',
      state: _stateOf(pool, disposition),
      transactionRef: stringField(pool, const [
        'transactionRef',
        'transactionReference',
        'reference',
      ]),
      finalDisposition: disposition,
      serviceType: stringField(pool, const ['serviceType', 'service']),
      amount: numberField(pool, const [
        'amountOrValueUnits',
        'amount',
        'value',
      ]),
      recipientPhone: stringField(pool, const [
        'recipientPhone',
        'recipient',
        'recipientNumber',
      ]),
      resolvedAt: dateField(pool, const ['resolvedAt', 'resolved_at']),
      failedReason: stringField(pool, const [
        'failedReason',
        'failureReason',
        'error',
        'reason',
      ]),
      decision: decisionPool == null
          ? null
          : RecipientDecision.fromJson(decisionPool),
    );
  }

  static TopupState _stateOf(Map<String, dynamic> pool, String? disposition) {
    final explicit = TopupState.fromApi(
      stringField(pool, const ['state', 'status', 'deliveryState']),
    );
    if (explicit != TopupState.unknown) return explicit;
    return switch (disposition?.toUpperCase()) {
      'DELIVERED_DIRECT' => TopupState.deliveredDirect,
      'SAVED_TO_LIDA_VALUE' => TopupState.deliveredLidaValue,
      'DELIVERY_FAILED' => TopupState.failed,
      _ => TopupState.unknown,
    };
  }

  @override
  List<Object?> get props => [
    topupOrderId,
    state,
    finalDisposition,
    resolvedAt,
    decision,
  ];
}
