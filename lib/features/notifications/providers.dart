import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/network/token_store.dart';
import '../auth/providers.dart';
import 'data/notification_models.dart';
import 'data/notifications_repository.dart';
import 'data/remote_notifications_repository.dart';

/// One-line swap point between the mock backend and the live API.
final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  // Rebuild on session change so a different user's inbox never leaks.
  ref.watch(authSessionProvider);
  return RemoteNotificationsRepository(ref.watch(apiClientProvider));
});

/// The API tracks delivery status (pending/sent/failed) but has no read
/// flag, so read state is persisted locally, per user.
final readNotificationsProvider =
    StateNotifierProvider<ReadNotificationsNotifier, Set<String>>((ref) {
      final userId = ref.watch(authSessionProvider)?.user.id ?? 'anon';
      return ReadNotificationsNotifier(ref.watch(sharedPrefsProvider), userId);
    });

class ReadNotificationsNotifier extends StateNotifier<Set<String>> {
  ReadNotificationsNotifier(this._prefs, this._userId)
    : super(_load(_prefs, _userId));

  final SharedPreferences _prefs;
  final String _userId;

  static String _key(String userId) => 'lidapay.read_notifications.$userId';

  static Set<String> _load(SharedPreferences prefs, String userId) {
    return (prefs.getStringList(_key(userId)) ?? const <String>[]).toSet();
  }

  Future<void> _save() =>
      _prefs.setStringList(_key(_userId), state.toList(growable: false));

  Future<void> markRead(String id, {Iterable<String>? relatedKeys}) {
    final toAdd = <String>{
      if (id.trim().isNotEmpty) id.trim(),
      if (relatedKeys != null)
        for (final k in relatedKeys)
          if (k.trim().isNotEmpty) k.trim(),
    };
    if (toAdd.isEmpty || toAdd.every(state.contains)) return Future.value();
    state = {...state, ...toAdd};
    return _save();
  }

  Future<void> markAll(Iterable<String> ids) {
    final toAdd = ids.map((i) => i.trim()).where((i) => i.isNotEmpty).toSet();
    if (toAdd.isEmpty || toAdd.every(state.contains)) return Future.value();
    state = {...state, ...toAdd};
    return _save();
  }
}

/// Optimistically dismissed notifications — the server stops returning them
/// after DELETE; this hides the row immediately without a refetch.
final dismissedNotificationsProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

/// Remote notification fetching. Only invalidated on refresh, account change,
/// or when new server data arrives.
final rawNotificationsProvider = FutureProvider<List<AppNotification>>((
  ref,
) async {
  return ref.watch(notificationsRepositoryProvider).getNotifications();
});

/// Synchronous combined view: takes raw notifications, dedupes same-kind/same-body
/// alerts across channels, and applies local read/dismissed state instantly in memory
/// without triggering background network reloads.
final notificationsProvider = Provider<AsyncValue<List<AppNotification>>>((ref) {
  final rawAsync = ref.watch(rawNotificationsProvider);
  final read = ref.watch(readNotificationsProvider);
  final dismissed = ref.watch(dismissedNotificationsProvider);

  return rawAsync.whenData((items) {
    final deduped = <AppNotification>[];
    final seen = <String, int>{};
    final mergedIds = <String, Set<String>>{};

    for (final n in items.where((n) => !dismissed.contains(n.id))) {
      final key = '${n.kind}|${n.displayMessage}';
      final prev = seen[key];
      if (prev != null &&
          n.createdAt.difference(deduped[prev].createdAt).abs() <
              const Duration(minutes: 10)) {
        mergedIds[key]!.add(n.id);
        if (deduped[prev].channel == 'email' && n.channel != 'email') {
          deduped[prev] = n;
        }
        continue;
      }
      seen[key] = deduped.length;
      mergedIds[key] = {n.id};
      deduped.add(n);
    }

    return deduped.map((n) {
      final key = '${n.kind}|${n.displayMessage}';
      final ids = mergedIds[key] ?? {n.id};
      final isLocallyRead = read.contains(n.id) ||
          read.contains(key) ||
          ids.any(read.contains);
      return (n.isRead || isLocallyRead) ? n.copyWith(isRead: true) : n;
    }).toList();
  });
});

/// Count driving the dashboard bell badge.
final unreadNotificationsProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).valueOrNull;
  if (list == null) return 0;
  return list.where((n) => !n.isRead).length;
});
