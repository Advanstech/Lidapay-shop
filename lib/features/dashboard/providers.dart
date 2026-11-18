import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import '../recipient_choice/data/recipient_models.dart';
import '../recipient_choice/providers.dart' as recipient;
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import 'data/dashboard_models.dart';
import 'data/dashboard_repository.dart';
import 'data/remote_dashboard_repository.dart';

/// One-line swap point between the mock backend and the live API. Watches
/// the session so repositories (and the FutureProviders below) refresh when
/// the signed-in user changes.
final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  final userId = ref.watch(authSessionProvider)?.user.id;
  return RemoteDashboardRepository(ref.watch(apiClientProvider), userId);
});

final walletSummaryProvider = FutureProvider<WalletSummary>((ref) {
  return ref.watch(dashboardRepositoryProvider).getWalletSummary();
});

final recentTransactionsProvider = FutureProvider<List<Transaction>>((ref) {
  return ref.watch(dashboardRepositoryProvider).getRecentTransactions();
});

final flashDealsProvider = FutureProvider<List<FlashDeal>>((ref) {
  return ref.watch(dashboardRepositoryProvider).getFlashDeals();
});

/// Visibility of balances on the wallet card (eye toggle).
final balanceHiddenProvider = StateProvider<bool>((ref) => false);

/// References whose topup order returned 404 — remembered for the session
/// so a stale `decision_pending` ledger row never re-polls a missing order.
final deadTopupRefsProvider = StateProvider<Set<String>>((_) => <String>{});

/// Metadata remembered for a sender-side parked top-up so background
/// settlement alerts always show the destination number even if `/status` omits it.
class TrackedPendingTopup {
  const TrackedPendingTopup({
    required this.topupOrderId,
    required this.recipient,
    required this.serviceLabel,
  });

  final String topupOrderId;
  final String recipient;
  final String serviceLabel;
}

/// Top-ups registered explicitly when the sender enters the waiting countdown
/// (Lida Value, MoMo/GTPay, or AdvansisPay return) so background polling runs
/// immediately even before the activity ledger refetches.
final trackedPendingTopupsProvider =
    StateProvider<Map<String, TrackedPendingTopup>>(
      (_) => const <String, TrackedPendingTopup>{},
    );

/// Set while [PendingTopupScreen] is actively on screen so the global alert
/// suppresses redundant snackbars when the user watches it settle live.
final activeWaitingTopupOrderIdProvider = StateProvider<String?>((_) => null);

void registerTrackedPendingTopup(
  WidgetRef ref, {
  required String topupOrderId,
  required String recipient,
  required String serviceLabel,
}) {
  final id = topupOrderId.trim();
  if (id.isEmpty) return;
  ref.read(trackedPendingTopupsProvider.notifier).update((current) {
    if (current.containsKey(id)) return current;
    return {
      ...current,
      id: TrackedPendingTopup(
        topupOrderId: id,
        recipient: recipient,
        serviceLabel: serviceLabel,
      ),
    };
  });
}

/// Formats a user-facing title and detail message when a parked top-up settles.
({String title, String body, bool failed}) describeSettledTopup(
  TopupOrderStatus status, {
  TrackedPendingTopup? tracked,
}) {
  final rawRecipient =
      status.recipientPhone ??
      status.decision?.recipientPhone ??
      tracked?.recipient;
  final recipient = (rawRecipient != null && rawRecipient.trim().isNotEmpty)
      ? rawRecipient.trim()
      : 'the recipient';
  final service = status.serviceType != null && status.serviceType!.isNotEmpty
      ? status.serviceLabel
      : (tracked?.serviceLabel ?? status.serviceLabel);
  return switch (status.state) {
    TopupState.deliveredDirect => (
      title: 'Top-up delivered',
      body:
          '$recipient accepted your $service — delivered directly to their line.',
      failed: false,
    ),
    TopupState.deliveredLidaValue => (
      title: 'Credited to Lida Value',
      body: status.decision?.resolvedSource == 'TIMEOUT'
          ? 'Credited to $recipient\'s Lida Value wallet for later use.'
          : '$recipient chose Lida Value — credited to their wallet for later use.',
      failed: false,
    ),
    TopupState.failed => (
      title: 'Top-up could not be delivered',
      body:
          'Top-up to $recipient failed — '
          '${Formatters.friendlyFailureReason(status.failedReason)}',
      failed: true,
    ),
    _ => (
      title: 'Top-up updated',
      body: 'Your $service top-up to $recipient has settled.',
      failed: false,
    ),
  };
}

/// The most recent pending top-up to reach a terminal state — set by the
/// tracker below so the app can alert the user anywhere (Home, Services,
/// Shop, History, Profile) even after leaving the countdown screen.
final recentlySettledTopupProvider = StateProvider<TopupOrderStatus?>(
  (_) => null,
);

/// Sender-side tracker for top-ups parked behind a recipient decision —
/// merges ledger rows flagged `decision_pending` with explicitly tracked
/// active transfers, then polls `GET /topups/{id}/status` until terminal.
final pendingRecipientTopupsProvider =
    StreamProvider.autoDispose<List<TopupOrderStatus>>((ref) async* {
      final dead = ref.watch(deadTopupRefsProvider);
      final tracked = ref.watch(trackedPendingTopupsProvider);
      List<Transaction> txs = const <Transaction>[];
      try {
        txs = await ref.watch(recentTransactionsProvider.future);
      } catch (_) {
        // Keep tracking explicitly started transfers even if the feed errs.
      }
      final ids = <String>{
        ...txs
            .where(
              (t) =>
                  t.isAwaitingRecipientDecision &&
                  t.reference.trim().isNotEmpty,
            )
            .map((t) => t.reference.trim()),
        ...tracked.keys,
      }.where((id) => !dead.contains(id)).toSet();
      if (ids.isEmpty) {
        yield const <TopupOrderStatus>[];
        return;
      }

      final repo = ref.watch(recipient.recipientChoiceRepositoryProvider);
      final live = <String, TopupOrderStatus>{};
      var settled = false;
      // The 4s cadence is only sustainable while the network answers.
      // A round with no successful response backs off (4s → 60s) so an
      // offline phone or a struggling backend is not hammered.
      var backoff = const Duration(seconds: 4);
      while (ids.isNotEmpty) {
        var anyAnswered = false;
        final entries = await Future.wait(
          ids.map((id) async {
            try {
              final status = await repo.getTopupStatus(id);
              anyAnswered = true;
              return MapEntry(id, status);
            } on ApiException catch (e) {
              if (e.statusCode != null) anyAnswered = true;
              // 404 = the ledger row is stale (order purged or never parked)
              // — blacklist it so it never re-seeds, and do NOT invalidate
              // the feed (the server-side row is stuck, a refetch changes
              // nothing and would loop seed→404→invalidate forever).
              if (e.statusCode == 404) {
                ids.remove(id);
                live.remove(id);
                ref.read(deadTopupRefsProvider.notifier).update(
                  (d) => {...d, id},
                );
                ref.read(trackedPendingTopupsProvider.notifier).update(
                  (m) => Map<String, TrackedPendingTopup>.from(m)..remove(id),
                );
              }
              return null;
            } catch (_) {
              return null; // transient — keep the last known state
            }
          }),
        );
        for (final entry in entries) {
          if (entry == null) continue;
          if (entry.value.isTerminal) {
            final meta = tracked[entry.key];
            final enriched =
                (entry.value.recipientPhone == null && meta != null)
                ? TopupOrderStatus(
                    topupOrderId: entry.value.topupOrderId,
                    state: entry.value.state,
                    transactionRef: entry.value.transactionRef,
                    finalDisposition: entry.value.finalDisposition,
                    serviceType:
                        entry.value.serviceType ?? meta.serviceLabel,
                    amount: entry.value.amount,
                    recipientPhone: meta.recipient,
                    resolvedAt: entry.value.resolvedAt,
                    failedReason: entry.value.failedReason,
                    decision: entry.value.decision,
                  )
                : entry.value;
            ids.remove(entry.key);
            live.remove(entry.key);
            settled = true;
            ref.read(trackedPendingTopupsProvider.notifier).update(
              (m) => Map<String, TrackedPendingTopup>.from(m)
                ..remove(entry.key),
            );
            ref.read(recentlySettledTopupProvider.notifier).state = enriched;
          } else {
            live[entry.key] = entry.value;
          }
        }
        if (settled) {
          settled = false;
          ref.invalidate(recentTransactionsProvider);
        }
        yield live.values.toList();
        if (ids.isNotEmpty) {
          await Future<void>.delayed(backoff);
          backoff = anyAnswered
              ? const Duration(seconds: 4)
              : Duration(
                  seconds: (backoff.inSeconds * 2).clamp(4, 60),
                );
        }
      }
    });
