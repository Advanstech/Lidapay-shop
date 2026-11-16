import 'recipient_models.dart';

/// Recipient-choice contract: a top-up to a registered recipient is parked
/// until they choose direct delivery or Lida Value (backend default on
/// timeout). The sender polls [getTopupStatus]; the recipient answers via
/// [respondToDecision].
abstract class RecipientChoiceRepository {
  /// Preflight used to decorate the confirm step — tells the sender whether
  /// the destination will be asked to choose. Never blocks a purchase; an
  /// unreachable check degrades to [RecipientEligibility.unregistered].
  Future<RecipientEligibility> checkEligibility({
    required String recipientPhone,
    required String serviceType,
    String? countryIsoCode,
  });

  /// `GET /recipient-decisions/pending` — every active pending decision
  /// waiting on the currently signed-in recipient (in-app recovery fallback
  /// when push notifications were delayed, muted, or missed).
  Future<List<RecipientDecision>> getPendingDecisions();

  /// `GET /recipient-decisions/{decisionId}` — the recipient's view of a
  /// parked delivery.
  Future<RecipientDecision> getDecision(String decisionId);

  /// `POST /recipient-decisions/{decisionId}/respond` with an idempotency key
  /// so retries never double-submit a choice. Returns the resolved decision.
  Future<RecipientDecision> respondToDecision({
    required String decisionId,
    required RecipientChoice choice,
    required String idempotencyKey,
  });

  /// `GET /topups/{topupOrderId}/status` — canonical delivery state; polled
  /// by both sides until a terminal disposition is reported.
  Future<TopupOrderStatus> getTopupStatus(String topupOrderId);
}
