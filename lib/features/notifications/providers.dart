import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/network/token_store.dart';
import '../auth/data/auth_models.dart';
import '../auth/providers.dart';
import 'data/notification_models.dart';
import 'data/notifications_repository.dart';
import 'data/remote_notifications_repository.dart';

String _userStorageKey(UserProfile? user) {
  if (user == null) return 'anon';
  for (final candidate in [
    user.id.trim(),
    user.email.trim().toLowerCase(),
    user.phoneNumber.trim(),
    user.username.trim().toLowerCase(),
  ]) {
    if (candidate.isNotEmpty) return candidate;
  }
  return 'anon';
}

/// One-line swap point between the mock backend and the live API.
final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  // Rebuild on session change so a different user's inbox never leaks.
  ref.watch(authSessionProvider.select((s) => _userStorageKey(s?.user)));
  return RemoteNotificationsRepository(ref.watch(apiClientProvider));
});

/// The API tracks delivery status (pending/sent/failed) but has no read
/// flag, so read state is persisted locally, per user.
final readNotificationsProvider =
    StateNotifierProvider<ReadNotificationsNotifier, Set<String>>((ref) {
      final userKey = ref.watch(
        authSessionProvider.select((s) => _userStorageKey(s?.user)),
      );
      final user = ref.read(authSessionProvider)?.user;
      final legacyKeys = <String>[
        if (user != null) ...[
          if (user.email.trim().isNotEmpty) user.email.trim().toLowerCase(),
          if (user.email.trim().isNotEmpty) user.email.trim(),
          if (user.phoneNumber.trim().isNotEmpty) user.phoneNumber.trim(),
          if (user.username.trim().isNotEmpty)
            user.username.trim().toLowerCase(),
          if (user.username.trim().isNotEmpty) user.username.trim(),
          '',
        ],
      ];
      return ReadNotificationsNotifier(
        ref.watch(sharedPrefsProvider),
        userKey,
        legacyKeys: legacyKeys,
      );
    });

class ReadNotificationsNotifier extends StateNotifier<Set<String>> {
  ReadNotificationsNotifier(
    this._prefs,
    this._userId, {
    List<String> legacyKeys = const <String>[],
  }) : super(_load(_prefs, _userId, legacyKeys));

  final SharedPreferences _prefs;
  final String _userId;

  static String _key(String userId) => 'lidapay.read_notifications.$userId';

  static Set<String> _load(
    SharedPreferences prefs,
    String userId,
    List<String> legacyKeys,
  ) {
    final ids = <String>{...(prefs.getStringList(_key(userId)) ?? const [])};
    for (final legacy in legacyKeys) {
      if (legacy == userId) continue;
      ids.addAll(prefs.getStringList(_key(legacy)) ?? const <String>[]);
    }
    return ids;
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

/// Synchronous combined view: takes raw notifications, filters to the active
/// user, dedupes same-kind/same-body alerts across channels, and applies local
/// read/dismissed state instantly in memory without triggering background
/// network reloads.
final notificationsProvider = Provider<AsyncValue<List<AppNotification>>>((ref) {
  final rawAsync = ref.watch(rawNotificationsProvider);
  final read = ref.watch(readNotificationsProvider);
  final dismissed = ref.watch(dismissedNotificationsProvider);
  final user = ref.watch(authSessionProvider.select((s) => s?.user));

  return rawAsync.whenData((items) {
    final deduped = <AppNotification>[];
    final seen = <String, int>{};
    final mergedIdsByIndex = <Set<String>>[];

    for (final n in items.where(
      (n) => n.belongsToUser(user) && !dismissed.contains(n.id),
    )) {
      final key = '${n.kind}|${n.displayMessage}';
      final prev = seen[key];
      if (prev != null &&
          n.createdAt.difference(deduped[prev].createdAt).abs() <
              const Duration(minutes: 10)) {
        mergedIdsByIndex[prev].add(n.id);
        if (deduped[prev].channel == 'email' && n.channel != 'email') {
          deduped[prev] = n;
        }
        continue;
      }
      seen[key] = deduped.length;
      mergedIdsByIndex.add({n.id});
      deduped.add(n);
    }

    final result = <AppNotification>[];
    for (var i = 0; i < deduped.length; i++) {
      final n = deduped[i];
      final ids = mergedIdsByIndex[i];
      if (ids.any(dismissed.contains)) continue;
      final decisionId = n.data['decisionId']?.toString().trim();
      final isLocallyRead =
          read.contains(n.id) ||
          ids.any(read.contains) ||
          read.contains('${n.kind}|${n.displayMessage}') ||
          (decisionId != null &&
              decisionId.isNotEmpty &&
              (read.contains('decision_$decisionId') ||
                  read.contains('decision|$decisionId')));
      result.add(
        n.copyWith(mergedIds: ids, isRead: n.isRead || isLocallyRead),
      );
    }
    return result;
  });
});

/// Count driving the dashboard bell badge.
final unreadNotificationsProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).valueOrNull;
  if (list == null) return 0;
  return list.where((n) => !n.isRead).length;
});
