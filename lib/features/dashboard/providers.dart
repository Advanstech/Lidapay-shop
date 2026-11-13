import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import '../recipient_choice/data/recipient_models.dart';
import '../recipient_choice/providers.dart' as recipient;
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
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

/// The most recent pending top-up to reach a terminal state — set by the
/// tracker below so the dashboard can toast the outcome (delivered, saved
/// to Lida Value, or failed with a reason) even when the sender wasn't on
/// the waiting screen. Cleared after it has been shown.
final recentlySettledTopupProvider = StateProvider<TopupOrderStatus?>(
  (_) => null,
);

/// Sender-side tracker for top-ups parked behind a recipient decision —
/// ledger rows flagged `decision_pending` seed the list, then each
/// `topupOrderId` is polled via `GET /topups/{id}/status` until it reaches a
/// terminal disposition. On settle the transaction feed is invalidated so
/// the activity list flips to the final outcome, and the card disappears.
final pendingRecipientTopupsProvider =
    StreamProvider.autoDispose<List<TopupOrderStatus>>((ref) async* {
      final dead = ref.watch(deadTopupRefsProvider);
      final txs = await ref.watch(recentTransactionsProvider.future);
      final ids = txs
          .where(
            (t) =>
                t.isAwaitingRecipientDecision && t.reference.trim().isNotEmpty,
          )
          .map((t) => t.reference.trim())
          .where((ref) => !dead.contains(ref))
          .toSet();
      if (ids.isEmpty) {
        yield const <TopupOrderStatus>[];
        return;
      }

      final repo = ref.watch(recipient.recipientChoiceRepositoryProvider);
      final live = <String, TopupOrderStatus>{};
      var settled = false;
      while (ids.isNotEmpty) {
        final entries = await Future.wait(
          ids.map((id) async {
            try {
              return MapEntry(id, await repo.getTopupStatus(id));
            } on ApiException catch (e) {
              // 404 = the ledger row is stale (order purged or never parked)
              // — blacklist it so it never re-seeds, and do NOT invalidate
              // the feed (the server-side row is stuck, a refetch changes
              // nothing and would loop seed→404→invalidate forever).
              if (e.statusCode == 404) {
                ids.remove(id);
                live.remove(id);
                ref.read(deadTopupRefsProvider.notifier).update(
                  (dead) => {...dead, id},
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
            ids.remove(entry.key);
            live.remove(entry.key);
            settled = true;
            ref.read(recentlySettledTopupProvider.notifier).state =
                entry.value;
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
          await Future<void>.delayed(const Duration(seconds: 4));
        }
      }
    });
