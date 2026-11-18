import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result of asking Play Core to run an update flow.
enum PlayUpdateAttempt {
  /// Play accepted the request (flexible download started, or the
  /// full-screen immediate flow took over).
  started,

  /// Play knows of no newer build on this install's track yet — typical on
  /// the first hours of a staged rollout.
  notAvailable,

  /// Play Core cannot run here: web, iOS, a sideloaded APK, or a missing
  /// plugin. The caller should fall back to the store listing.
  unsupported,

  /// The user dismissed Play's own sheet.
  declined,

  /// Play started and then failed the flow.
  failed,
}

/// Thin, fail-safe wrapper over Google Play Core in-app updates.
///
/// Nothing here throws: every Play/plugin error is translated into a
/// [PlayUpdateAttempt] so the gate can degrade to opening the Play listing or
/// to showing the prompt again later. In-app updates only work for builds
/// installed from Play; `ERROR_API_NOT_AVAILABLE` on a sideloaded APK is
/// expected, not a bug.
class PlayUpdateService {
  /// Play Core in-app updates are Android-only (and never available on web).
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Download in the background; the app stays usable and installs after the
  /// user restarts. Used for optional and required updates alike, because a
  /// forced update must also finish cleanly after the download.
  Future<PlayUpdateAttempt> startFlexibleUpdate() async {
    final info = await _check();
    if (info == null) return PlayUpdateAttempt.unsupported;
    if (!_hasUpdate(info) || !info.flexibleUpdateAllowed) {
      return PlayUpdateAttempt.notAvailable;
    }
    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      return _attemptFrom(result);
    } on MissingPluginException {
      return PlayUpdateAttempt.unsupported;
    } on PlatformException catch (e) {
      debugPrint('Play flexible update failed: ${e.code}');
      return PlayUpdateAttempt.failed;
    } catch (e) {
      // A missing Play Core class or a broken channel must not escape as an
      // unhandled async error — the gate simply degrades.
      debugPrint('Play flexible update unavailable: $e');
      return PlayUpdateAttempt.unsupported;
    }
  }

  /// Full-screen, blocking Play flow. Reserved for builds below the
  /// backend's minimum supported version.
  Future<PlayUpdateAttempt> startImmediateUpdate() async {
    final info = await _check();
    if (info == null) return PlayUpdateAttempt.unsupported;
    if (!_hasUpdate(info) || !info.immediateUpdateAllowed) {
      return PlayUpdateAttempt.notAvailable;
    }
    try {
      final result = await InAppUpdate.performImmediateUpdate();
      return _attemptFrom(result);
    } on MissingPluginException {
      return PlayUpdateAttempt.unsupported;
    } on PlatformException catch (e) {
      debugPrint('Play immediate update failed: ${e.code}');
      return PlayUpdateAttempt.failed;
    } catch (e) {
      debugPrint('Play immediate update unavailable: $e');
      return PlayUpdateAttempt.unsupported;
    }
  }

  /// Installs the flexible update that already finished downloading.
  Future<bool> completeFlexibleUpdate() async {
    if (!isSupported) return false;
    try {
      await InAppUpdate.completeFlexibleUpdate();
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('Play complete update failed: ${e.code}');
      return false;
    } catch (e) {
      debugPrint('Play complete update unavailable: $e');
      return false;
    }
  }

  /// Progress of a flexible download. Empty off Android.
  Stream<InstallStatus> get installStatus {
    if (!isSupported) return const Stream<InstallStatus>.empty();
    try {
      return InAppUpdate.installUpdateListener;
    } catch (_) {
      return const Stream<InstallStatus>.empty();
    }
  }

  /// Opens the Play listing. Only `https` Play/App Store hosts are launched —
  /// the URL comes from the backend, so it is untrusted input.
  Future<bool> openStoreListing(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !_isStoreUri(uri)) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static bool _isStoreUri(Uri uri) {
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'play.google.com' ||
        host.endsWith('.play.google.com') ||
        host == 'apps.apple.com' ||
        host.endsWith('.apps.apple.com');
  }

  static bool _hasUpdate(AppUpdateInfo info) =>
      info.updateAvailability == UpdateAvailability.updateAvailable ||
      info.updateAvailability ==
          UpdateAvailability.developerTriggeredUpdateInProgress;

  static PlayUpdateAttempt _attemptFrom(AppUpdateResult result) =>
      switch (result) {
        AppUpdateResult.success => PlayUpdateAttempt.started,
        AppUpdateResult.userDeniedUpdate => PlayUpdateAttempt.declined,
        AppUpdateResult.inAppUpdateFailed => PlayUpdateAttempt.failed,
      };

  Future<AppUpdateInfo?> _check() async {
    if (!isSupported) return null;
    try {
      return await InAppUpdate.checkForUpdate();
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      // ERROR_API_NOT_AVAILABLE: sideloaded build, or Play has not seen the
      // release yet. Caller falls back to the listing.
      debugPrint('Play update check unavailable: ${e.code}');
      return null;
    } catch (e) {
      debugPrint('Play update check failed: $e');
      return null;
    }
  }
}
