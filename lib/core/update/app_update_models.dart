import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show immutable;

/// How urgently this install needs the newest store release.
enum UpdateUrgency {
  /// This build is current, the policy says nothing, or the check failed.
  none,

  /// A newer build exists; the user may keep using this one for now.
  optional,

  /// This build is below the backend's minimum supported build. Blocking.
  required,
}

/// The backend's app-version policy for one platform.
///
/// The whole gate is fail-open: an unreachable endpoint, a route the backend
/// has not shipped yet, or an unparseable payload all collapse to
/// [AppVersionPolicy.none], which never prompts or blocks anyone. A version
/// check must never be able to brick a paying customer's app.
@immutable
class AppVersionPolicy extends Equatable {
  const AppVersionPolicy({
    this.minimumBuild,
    this.minimumVersion,
    this.latestBuild,
    this.latestVersion,
    this.storeUrl,
    this.message,
  });

  /// Nothing to enforce (also what an empty payload parses to).
  static const none = AppVersionPolicy();

  /// Builds (Android `versionCode`) below this are forced to update.
  final int? minimumBuild;

  /// Version-name form of [minimumBuild], used when the backend publishes
  /// names only (`1.2.0`).
  final String? minimumVersion;

  /// Newest published build. Anything older gets an optional prompt.
  final int? latestBuild;

  /// Version-name form of [latestBuild].
  final String? latestVersion;

  /// Store listing to open when Play Core's own sheet is unavailable.
  final String? storeUrl;

  /// Operator copy for the prompt ("Faster top-ups, new rewards").
  final String? message;

  bool get isEmpty =>
      minimumBuild == null &&
      minimumVersion == null &&
      latestBuild == null &&
      latestVersion == null;

  /// True when the policy knows about a build newer than nothing at all.
  bool get hasUpdate => latestBuild != null || latestVersion != null;

  /// Parses the shapes this route has been proposed in:
  /// - flat: `{ "minimumBuild": 34, "latestBuild": 36 }`
  /// - enveloped: `{ "data": { ... } }`
  /// - per platform: `{ "android": { ... }, "ios": { ... } }` (either at the
  ///   top level or under `platforms`).
  ///
  /// Field aliases are accepted because the backend team names these
  /// differently across services (camelCase DTOs, snake_case aggregates).
  factory AppVersionPolicy.fromApiJson(
    Map<String, dynamic> json, {
    String platform = 'ANDROID',
  }) {
    var node = json;
    final data = node['data'];
    if (data is Map) node = Map<String, dynamic>.from(data);

    final key = platform.toLowerCase();
    final platforms = node['platforms'];
    if (platforms is Map && platforms[key] is Map) {
      node = Map<String, dynamic>.from(platforms[key] as Map);
    } else if (node[key] is Map) {
      node = Map<String, dynamic>.from(node[key] as Map);
    }

    return AppVersionPolicy(
      minimumBuild: _asInt(node, const [
        'minimumBuild',
        'minimum_build',
        'minBuild',
        'min_build',
        'minimumVersionCode',
        'minimum_version_code',
        'minSupportedBuild',
        'minimumSupportedBuild',
      ]),
      minimumVersion: _asString(node, const [
        'minimumVersion',
        'minimum_version',
        'minVersion',
        'min_version',
        'minSupportedVersion',
      ]),
      latestBuild: _asInt(node, const [
        'latestBuild',
        'latest_build',
        'latestVersionCode',
        'latest_version_code',
        'versionCode',
        'version_code',
        'buildNumber',
        'build_number',
        'build',
      ]),
      latestVersion: _asString(node, const [
        'latestVersion',
        'latest_version',
        'versionName',
        'version_name',
        'version',
      ]),
      storeUrl: _asString(node, const [
        'storeUrl',
        'store_url',
        'playStoreUrl',
        'play_store_url',
        'updateUrl',
        'update_url',
        'url',
      ]),
      message: _asString(node, const [
        'message',
        'updateMessage',
        'update_message',
        'notes',
        'releaseNotes',
        'release_notes',
      ]),
    );
  }

  /// Decides what to do with this install.
  ///
  /// Builds are compared first because they are monotonic across releases;
  /// version names are only consulted when the backend publishes no build.
  /// An unknown local build (`0`, e.g. a platform probe failure) never gates.
  UpdateUrgency urgencyFor({
    required int currentBuild,
    String? currentVersion,
  }) {
    if (currentBuild <= 0) return UpdateUrgency.none;

    final minBuild = minimumBuild;
    if (minBuild != null && currentBuild < minBuild)
      return UpdateUrgency.required;

    final newestBuild = latestBuild;
    if (newestBuild != null && currentBuild < newestBuild) {
      return UpdateUrgency.optional;
    }
    if (newestBuild != null) return UpdateUrgency.none;

    final version = currentVersion?.trim();
    if (version == null || version.isEmpty) return UpdateUrgency.none;

    final minVersion = minimumVersion?.trim();
    if (minVersion != null && minVersion.isNotEmpty) {
      if (compareVersionNames(version, minVersion) < 0) {
        return UpdateUrgency.required;
      }
      return UpdateUrgency.none;
    }

    final newestVersion = latestVersion?.trim();
    if (newestVersion != null && newestVersion.isNotEmpty) {
      if (compareVersionNames(version, newestVersion) < 0) {
        return UpdateUrgency.optional;
      }
    }
    return UpdateUrgency.none;
  }

  static int? _asInt(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is num) return value.toInt();
      if (value is String) {
        final digits = RegExp(r'\d+').firstMatch(value)?.group(0);
        final parsed = digits == null ? null : int.tryParse(digits);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static String? _asString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is num) return value.toString();
    }
    return null;
  }

  @override
  List<Object?> get props => [
    minimumBuild,
    minimumVersion,
    latestBuild,
    latestVersion,
    storeUrl,
    message,
  ];
}

/// Compares dotted version names segment by segment (`1.1.10` > `1.1.9`).
///
/// Non-numeric suffixes (`1.2.0-beta.1`, `1.2.0+34`) are ignored so a
/// pre-release name never reads as newer than its release. Returns a negative
/// number when [a] is older, zero when equal, positive when newer.
int compareVersionNames(String a, String b) {
  List<int> segments(String value) {
    final core = value.split('+').first.split('-').first;
    return core
        .split('.')
        .map(
          (part) =>
              int.tryParse(RegExp(r'\d+').firstMatch(part)?.group(0) ?? '') ??
              0,
        )
        .toList(growable: false);
  }

  final left = segments(a.trim());
  final right = segments(b.trim());
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}
