import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_payload.dart';
import 'recipient_choice_repository.dart';
import 'recipient_models.dart';

/// Live recipient-choice endpoints. The eligibility check doubles as a phone
/// normalisation probe: Ghana numbers are tried in both `0…` and `233…`
/// shapes because a registered account may be stored under either.
class RemoteRecipientChoiceRepository implements RecipientChoiceRepository {
  RemoteRecipientChoiceRepository(this._api);

  final ApiClient _api;

  @override
  Future<RecipientEligibility> checkEligibility({
    required String recipientPhone,
    required String serviceType,
    String? countryIsoCode,
  }) async {
    RecipientEligibility? lastParsed;
    for (final phone in _phoneCandidates(recipientPhone, countryIsoCode)) {
      try {
        final raw = await _api.postRaw(
          ApiEndpoints.recipientEligibility,
          body: {
            'recipientPhone': phone,
            'serviceType': serviceType,
            if (countryIsoCode != null && countryIsoCode.isNotEmpty)
              'countryIsoCode': countryIsoCode,
          },
        );
        if (raw is Map<String, dynamic>) {
          final parsed = RecipientEligibility.fromJson(raw);
          if (parsed.willPromptRecipient) return parsed;
          lastParsed ??= parsed;
        }
      } catch (_) {
        // Try the alternate phone shape, then degrade to unregistered.
      }
    }
    return lastParsed ?? const RecipientEligibility.unregistered();
  }

  @override
  Future<RecipientDecision> getDecision(String decisionId) async {
    final raw = await _api.getRaw(
      ApiEndpoints.recipientDecision(decisionId.trim()),
    );
    return RecipientDecision.fromJson(asMap(raw));
  }

  @override
  Future<RecipientDecision> respondToDecision({
    required String decisionId,
    required RecipientChoice choice,
    required String idempotencyKey,
  }) async {
    final raw = await _api.postRaw(
      ApiEndpoints.recipientDecisionRespond(decisionId.trim()),
      body: {'choice': choice.apiValue},
      headers: {'X-Idempotency-Key': idempotencyKey},
    );
    final pool = asMap(raw);
    // The respond payload carries the decision fields at the top level with
    // an optional nested `deliveryResult`; merge so either shape parses.
    if (pool['deliveryResult'] is Map) {
      return RecipientDecision.fromJson(pool);
    }
    return getDecision(decisionId);
  }

  @override
  Future<TopupOrderStatus> getTopupStatus(String topupOrderId) async {
    final raw = await _api.getRaw(
      ApiEndpoints.topupStatus(topupOrderId.trim()),
    );
    return TopupOrderStatus.fromJson(asMap(raw));
  }

  /// Ghana numbers exist in the backend under both local (`0…`) and
  /// international (`233…`) shapes; probe the alternate when the primary
  /// lookup fails or reports unregistered.
  static List<String> _phoneCandidates(String phone, String? countryIso) {
    final candidates = <String>[phone.trim()];
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final isGhana =
        (countryIso ?? '').toUpperCase() == 'GH' ||
        digits.startsWith('233') ||
        digits.startsWith('0');
    if (isGhana) {
      if (digits.startsWith('233') && digits.length >= 12) {
        candidates.add('0${digits.substring(3)}');
      } else if (digits.startsWith('0') && digits.length == 10) {
        candidates.add('233${digits.substring(1)}');
      } else if (digits.length == 9) {
        candidates.add('233$digits');
      }
    }
    return candidates.toSet().where((p) => p.isNotEmpty).toList();
  }
}
