import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/providers.dart';
import 'data/recipient_choice_repository.dart';
import 'data/recipient_models.dart';
import 'data/remote_recipient_choice_repository.dart';

final recipientChoiceRepositoryProvider = Provider<RecipientChoiceRepository>(
  (ref) => RemoteRecipientChoiceRepository(ref.watch(apiClientProvider)),
);

/// Active pending recipient decisions recovered via
/// `GET /api/v1/recipient-decisions/pending` so incoming gifts surface reliably
/// even when OS push notifications are muted, delayed, or missed.
final pendingRecipientDecisionsProvider =
    StateNotifierProvider<
      PendingRecipientDecisionsNotifier,
      List<RecipientDecision>
    >((ref) {
      final session = ref.watch(authSessionProvider);
      final user = session?.user;
      final userKey = user == null
          ? 'anon'
          : (user.id.isNotEmpty
                ? user.id
                : (user.phoneNumber.isNotEmpty
                      ? user.phoneNumber
                      : user.username));
      final notifier = PendingRecipientDecisionsNotifier(
        ref.watch(recipientChoiceRepositoryProvider),
        hasSession: session != null,
        userKey: userKey,
      );
      if (session != null) {
        Future<void>.microtask(notifier.refresh);
      }
      return notifier;
    });

class PendingRecipientDecisionsNotifier
    extends StateNotifier<List<RecipientDecision>> {
  PendingRecipientDecisionsNotifier(
    this._repo, {
    required bool hasSession,
    required String userKey,
  }) : _hasSession = hasSession,
       _userKey = userKey,
       super(const []);

  final RecipientChoiceRepository _repo;
  final bool _hasSession;
  final String _userKey;
  final Set<String> _surfacedIds = <String>{};
  bool _refreshing = false;

  String get userKey => _userKey;

  Future<void> refresh() async {
    if (!_hasSession || _refreshing) return;
    _refreshing = true;
    try {
      final items = await _repo.getPendingDecisions();
      if (!mounted) return;
      final now = DateTime.now();
      state = items
          .where(
            (d) =>
                d.isPending &&
                (d.expiresAt == null || d.expiresAt!.isAfter(now)),
          )
          .toList();
    } catch (_) {
      // Non-fatal recovery probe — keep the current list intact on offline/5xx.
    } finally {
      _refreshing = false;
    }
  }

  /// Returns the next pending decision not yet auto-surfaced for this
  /// user/session, marking it claimed so it is only opened once automatically.
  RecipientDecision? claimNextToSurface() {
    final now = DateTime.now();
    for (final d in state) {
      final active =
          d.isPending && (d.expiresAt == null || d.expiresAt!.isAfter(now));
      if (active && _surfacedIds.add(d.decisionId)) {
        return d;
      }
    }
    return null;
  }
}

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
      var disposed = false;
      ref.onDispose(() => disposed = true);
      TopupOrderStatus? last;
      while (!disposed) {
        try {
          final status = await repo.getTopupStatus(topupOrderId);
          if (disposed) return;
          // Skip unchanged snapshots — each yield rebuilds the pending
          // screen, and rebuilds while a pointer hovers trip a debug-only
          // Flutter web mouse-tracker assertion.
          if (status != last) {
            last = status;
            yield status;
          }
          if (status.isTerminal || disposed) return;
        } catch (_) {
          if (disposed) return;
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
