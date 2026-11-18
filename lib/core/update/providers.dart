import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart' show InstallStatus;
import 'package:shared_preferences/shared_preferences.dart';

import '../device/device_identity.dart';
import '../network/api_client.dart';
import '../network/token_store.dart';
import 'app_update_models.dart';
import 'app_update_repository.dart';
import 'play_update_service.dart';

/// Play listing used when the backend sends no store URL of its own.
const String defaultPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.advansistechnologies.lidapay';

final appUpdateRepositoryProvider = Provider<AppUpdateRepository>((ref) {
  return RemoteAppUpdateRepository(ref.watch(apiClientProvider));
});

final playUpdateServiceProvider = Provider<PlayUpdateService>((_) {
  return PlayUpdateService();
});

final appUpdateControllerProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>((ref) {
      return AppUpdateController(ref);
    });

@immutable
class AppUpdateState extends Equatable {
  const AppUpdateState({
    this.urgency = UpdateUrgency.none,
    this.policy = AppVersionPolicy.none,
    this.checking = false,
    this.starting = false,
    this.downloading = false,
    this.readyToInstall = false,
    this.playUnavailable = false,
  });

  /// What the gate should do right now.
  final UpdateUrgency urgency;

  /// Policy behind [urgency]; also carries the operator copy to show.
  final AppVersionPolicy policy;

  /// A policy fetch is in flight.
  final bool checking;

  /// Play's sheet is being opened / a download is being requested.
  final bool starting;

  /// A flexible download is running in the background.
  final bool downloading;

  /// The flexible download finished; a restart installs it.
  final bool readyToInstall;

  /// Play Core could not run the flow (sideload, rollout lag), so the gate
  /// falls back to opening the Play listing.
  final bool playUnavailable;

  /// The app must be updated before it can be used.
  bool get isBlocking => urgency == UpdateUrgency.required;

  /// A prompt should be on screen.
  bool get showsPrompt => isBlocking || urgency == UpdateUrgency.optional;

  @override
  List<Object?> get props => [
    urgency,
    policy,
    checking,
    starting,
    downloading,
    readyToInstall,
    playUnavailable,
  ];

  AppUpdateState copyWith({
    UpdateUrgency? urgency,
    AppVersionPolicy? policy,
    bool? checking,
    bool? starting,
    bool? downloading,
    bool? readyToInstall,
    bool? playUnavailable,
  }) {
    return AppUpdateState(
      urgency: urgency ?? this.urgency,
      policy: policy ?? this.policy,
      checking: checking ?? this.checking,
      starting: starting ?? this.starting,
      downloading: downloading ?? this.downloading,
      readyToInstall: readyToInstall ?? this.readyToInstall,
      playUnavailable: playUnavailable ?? this.playUnavailable,
    );
  }
}

/// Owns the update decision: fetches the backend policy, applies the
/// "remind me later" snooze, and drives the Play Core flows.
///
/// The gate is Android-only. On web and desktop every method is a no-op so
/// the same widget tree can be shared across platforms and tests.
class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(this._ref) : super(const AppUpdateState());

  /// How long a resumed app waits before re-asking the backend.
  static const recheckAfter = Duration(hours: 6);

  /// How long "Later" silences an optional prompt.
  static const remindAfter = Duration(days: 3);

  static const _snoozeKeyPrefix = 'lidapay.update.snoozed_until.';

  final Ref _ref;
  DateTime? _lastCheckedAt;
  StreamSubscription<InstallStatus>? _installSub;

  /// Checks for a newer build. Throttled to once per [recheckAfter] unless
  /// [force] is set; concurrent calls are coalesced.
  Future<void> check({bool force = false}) async {
    if (state.checking || state.readyToInstall) return;
    if (!_enabled) return;

    final now = DateTime.now();
    final last = _lastCheckedAt;
    if (!force && last != null && now.difference(last) < recheckAfter) return;
    _lastCheckedAt = now;

    state = state.copyWith(checking: true, playUnavailable: false);

    final identity = _ref.read(deviceIdentityProvider);
    final currentBuild = int.tryParse(identity.buildNumber) ?? 0;
    final policy = await _ref
        .read(appUpdateRepositoryProvider)
        .fetchPolicy(
          platform: identity.platform,
          appVersion: identity.appVersion,
          buildNumber: currentBuild,
        );
    if (!mounted) return;

    final urgency = policy.urgencyFor(
      currentBuild: currentBuild,
      currentVersion: identity.appVersion,
    );
    final snoozed =
        urgency == UpdateUrgency.optional && await _isSnoozed(policy);
    if (!mounted) return;

    state = state.copyWith(
      checking: false,
      policy: policy,
      urgency: snoozed ? UpdateUrgency.none : urgency,
    );
  }

  /// Optional prompt's "Later": silence it for [remindAfter].
  Future<void> remindLater() async {
    if (state.urgency != UpdateUrgency.optional) return;
    await _snooze(state.policy);
    if (!mounted) return;
    state = state.copyWith(urgency: UpdateUrgency.none);
  }

  /// Runs the Play flow: immediate when the build is below the minimum,
  /// flexible otherwise. Falls back to the store listing whenever Play Core
  /// cannot take over.
  Future<void> startUpdate() async {
    if (state.starting) return;
    final service = _ref.read(playUpdateServiceProvider);
    final required = state.isBlocking;
    state = state.copyWith(starting: true, playUnavailable: false);

    final attempt = required
        ? await service.startImmediateUpdate()
        : await service.startFlexibleUpdate();
    if (!mounted) return;

    switch (attempt) {
      case PlayUpdateAttempt.started:
        // Keep the prompt (and therefore its progress bar and final restart
        // action) on screen while a flexible download runs.
        state = state.copyWith(starting: false, downloading: !required);
        if (!required) _listenForInstall();
        return;
      case PlayUpdateAttempt.declined:
        state = state.copyWith(starting: false);
        return;
      case PlayUpdateAttempt.notAvailable:
      case PlayUpdateAttempt.unsupported:
      case PlayUpdateAttempt.failed:
        final opened = await service.openStoreListing(_storeUrl);
        if (!mounted) return;
        state = state.copyWith(starting: false, playUnavailable: true);
        if (!opened) {
          debugPrint(
            'Could not open the store listing for $defaultPlayStoreUrl',
          );
        }
    }
  }

  /// Opens the Play listing directly (fallback button).
  Future<void> openStoreListing() async {
    await _ref.read(playUpdateServiceProvider).openStoreListing(_storeUrl);
  }

  /// Installs a flexible update that has finished downloading.
  Future<void> restartToInstall() async {
    final done = await _ref
        .read(playUpdateServiceProvider)
        .completeFlexibleUpdate();
    if (!mounted) return;
    if (done) {
      // Play restarts the process; drop the card so it cannot linger if the
      // install is deferred.
      state = state.copyWith(readyToInstall: false);
    }
  }

  /// Hides the "restart to finish" card for this session.
  void dismissReady() {
    state = state.copyWith(readyToInstall: false, downloading: false);
  }

  bool get _enabled => _ref.read(playUpdateServiceProvider).isSupported;

  String get _storeUrl {
    final fromPolicy = state.policy.storeUrl;
    return fromPolicy != null && fromPolicy.isNotEmpty
        ? fromPolicy
        : defaultPlayStoreUrl;
  }

  void _listenForInstall() {
    _installSub?.cancel();
    _installSub = _ref.read(playUpdateServiceProvider).installStatus.listen((
      status,
    ) {
      if (!mounted) return;
      switch (status) {
        case InstallStatus.downloaded:
          state = state.copyWith(downloading: false, readyToInstall: true);
        case InstallStatus.downloading:
        case InstallStatus.pending:
          state = state.copyWith(downloading: true);
        case InstallStatus.failed:
          state = state.copyWith(downloading: false);
        case InstallStatus.unknown:
        case InstallStatus.installing:
        case InstallStatus.installed:
        case InstallStatus.canceled:
          break;
      }
    }, onError: (_) {});
  }

  Future<bool> _isSnoozed(AppVersionPolicy policy) async {
    final until = await _snoozedUntil(policy);
    return until != null && DateTime.now().isBefore(until);
  }

  Future<void> _snooze(AppVersionPolicy policy) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final until = DateTime.now().add(remindAfter);
    await prefs.setInt(_snoozeKey(policy), until.millisecondsSinceEpoch);
  }

  Future<DateTime?> _snoozedUntil(AppVersionPolicy policy) async {
    final epoch = _prefs?.getInt(_snoozeKey(policy));
    if (epoch == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(epoch);
  }

  String _snoozeKey(AppVersionPolicy policy) {
    final marker = policy.latestBuild ?? policy.latestVersion ?? 'latest';
    return '$_snoozeKeyPrefix$marker';
  }

  SharedPreferences? get _prefs {
    try {
      return _ref.read(sharedPrefsProvider);
    } catch (_) {
      // Unwired containers (isolated unit tests) simply lose the snooze.
      return null;
    }
  }

  @override
  void dispose() {
    _installSub?.cancel();
    super.dispose();
  }
}
