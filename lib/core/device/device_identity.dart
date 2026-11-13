import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';

/// Who this install is, as reported to the backend on OTP verify and FCM
/// token registration. Never contains hardware identifiers (IMEI,
/// ANDROID_ID, IDFA): [deviceId] is a random app-scoped UUID that resets on
/// reinstall — Play/App Store privacy friendly.
@immutable
class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.platform,
    required this.appVersion,
    required this.buildNumber,
    required this.locale,
    required this.model,
    required this.osVersion,
    required this.manufacturer,
  });

  final String deviceId;

  /// `ANDROID` | `IOS` | `WEB` — the backend's RegisterDeviceTokenDto enum.
  final String platform;
  final String appVersion;
  final String buildNumber;

  /// `en_GH` style, matching the handoff examples.
  final String locale;
  final String model;
  final String osVersion;

  /// e.g. `samsung` — used to apply OEM-specific UI workarounds.
  final String manufacturer;

  bool get isSamsung => manufacturer.toLowerCase() == 'samsung';

  /// ISO-3166 alpha-2 from the device locale; a hint only — the user's
  /// selected destination country is authoritative.
  String? get localeCountry {
    final parts = locale.split(RegExp('[_-]'));
    return parts.length > 1 && parts.last.length == 2
        ? parts.last.toUpperCase()
        : null;
  }

  static const fallback = DeviceIdentity(
    deviceId: 'unknown',
    platform: 'ANDROID',
    appVersion: AppConstants.appVersion,
    buildNumber: '0',
    locale: AppConstants.defaultLocale,
    model: '',
    osVersion: '',
    manufacturer: '',
  );
}

/// Overridden in `main()` with the resolved identity; tests get [fallback].
final deviceIdentityProvider = Provider<DeviceIdentity>(
  (ref) => DeviceIdentity.fallback,
);

class DeviceIdentityLoader {
  static const _deviceIdKey = 'lidapay.device_id';

  /// Resolves the identity. Never throws — each probe falls back
  /// independently so a misbehaving plugin can't block app start.
  static Future<DeviceIdentity> load(SharedPreferences prefs) async {
    var deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }

    var appVersion = AppConstants.appVersion;
    var buildNumber = '0';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
      buildNumber = info.buildNumber;
    } catch (_) {}

    var platform = 'WEB';
    var model = '';
    var osVersion = '';
    var manufacturer = '';
    try {
      final plugin = DeviceInfoPlugin();
      if (kIsWeb) {
        platform = 'WEB';
      } else if (Platform.isAndroid) {
        platform = 'ANDROID';
        final a = await plugin.androidInfo;
        model = a.model;
        manufacturer = a.manufacturer;
        osVersion = 'Android ${a.version.release} (SDK ${a.version.sdkInt})';
      } else if (Platform.isIOS) {
        platform = 'IOS';
        final i = await plugin.iosInfo;
        model = i.utsname.machine;
        manufacturer = 'apple';
        osVersion = '${i.systemName} ${i.systemVersion}';
      }
    } catch (_) {}

    final l = PlatformDispatcher.instance.locale;
    final locale = l.countryCode == null || l.countryCode!.isEmpty
        ? AppConstants.defaultLocale
        : '${l.languageCode}_${l.countryCode}';

    return DeviceIdentity(
      deviceId: deviceId,
      platform: platform,
      appVersion: appVersion,
      buildNumber: buildNumber,
      locale: locale,
      model: model,
      osVersion: osVersion,
      manufacturer: manufacturer,
    );
  }
}
