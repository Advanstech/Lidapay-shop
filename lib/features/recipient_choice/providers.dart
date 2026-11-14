import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import 'data/recipient_choice_repository.dart';
import 'data/recipient_models.dart';
import 'data/remote_recipient_choice_repository.dart';

final recipientChoiceRepositoryProvider = Provider<RecipientChoiceRepository>(
  (ref) => RemoteRecipientChoiceRepository(ref.watch(apiClientProvider)),
);

/// Preflight for the wizard confirm step — tells the sender whether the
/// destination is a registered account that will be asked to choose between
/// direct delivery and Lida Value. Non-blocking: a failed probe resolves to
/// "unregistered" and the banner simply doesn't show.
final recipientEligibilityProvider = FutureProvider.autoDispose
    .family<RecipientEligibility, ({String phone, String service, String iso})>(
      (ref, query) => ref
          .watch(recipientChoiceRepositoryProvider)
          .checkEligibility(
            recipientPhone: query.phone,
            serviceType: query.service,
            countryIsoCode: query.iso,
          ),
    );

/// The recipient-facing decision record, keyed by `decisionId` (from the
/// push payload or a notification row). `ref.invalidate` refetches.
final recipientDecisionProvider = FutureProvider.autoDispose
    .family<RecipientDecision, String>(
      (ref, decisionId) =>
          ref.watch(recipientChoiceRepositoryProvider).getDecision(decisionId),
    );

/// Sender- and recipient-side settlement poll. Emits the canonical
/// `GET /topups/{id}/status` snapshot every few seconds until a terminal
/// disposition, then completes. Transient failures are swallowed so a flaky
/// connection never flips the UI to an error state.
final topupStatusTrackerProvider = StreamProvider.autoDispose
    .family<TopupOrderStatus, String>((ref, topupOrderId) async* {
      final repo = ref.watch(recipientChoiceRepositoryProvider);
      TopupOrderStatus? last;
      while (true) {
        try {
          final status = await repo.getTopupStatus(topupOrderId);
          // Skip unchanged snapshots — each yield rebuilds the pending
          // screen, and rebuilds while a pointer hovers trip a debug-only
          // Flutter web mouse-tracker assertion.
          if (status != last) {
            last = status;
            yield status;
          }
          if (status.isTerminal) return;
        } catch (_) {
          // Transient — keep polling; a parked top-up settles server-side.
        }
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    });

/// One-shot idempotency key for a decision response — the backend requires
/// `X-Idempotency-Key` so retried taps can't double-submit a choice.
String newDecisionIdempotencyKey(String decisionId, RecipientChoice choice) {
  final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final tail = Random.secure().nextInt(0xFFFFFFF).toRadixString(16);
  return '$decisionId-${choice.apiValue}-$stamp-$tail';
}
