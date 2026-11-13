import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/core/device/device_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceIdentity', () {
    test('isSamsung identifies samsung devices regardless of casing', () {
      const samsung1 = DeviceIdentity(
        deviceId: 'd1',
        platform: 'ANDROID',
        appVersion: '1.0.0',
        buildNumber: '1',
        locale: 'en_GH',
        model: 'SM-G998B',
        osVersion: 'Android 14',
        manufacturer: 'samsung',
      );
      expect(samsung1.isSamsung, isTrue);

      const samsung2 = DeviceIdentity(
        deviceId: 'd2',
        platform: 'ANDROID',
        appVersion: '1.0.0',
        buildNumber: '1',
        locale: 'en_GH',
        model: 'SM-S918B',
        osVersion: 'Android 14',
        manufacturer: 'SAMSUNG',
      );
      expect(samsung2.isSamsung, isTrue);

      const pixel = DeviceIdentity(
        deviceId: 'd3',
        platform: 'ANDROID',
        appVersion: '1.0.0',
        buildNumber: '1',
        locale: 'en_GH',
        model: 'Pixel 8',
        osVersion: 'Android 14',
        manufacturer: 'Google',
      );
      expect(pixel.isSamsung, isFalse);
    });

    test('localeCountry parses alpha-2 country from locale', () {
      const gh = DeviceIdentity(
        deviceId: 'd1',
        platform: 'ANDROID',
        appVersion: '1.0.0',
        buildNumber: '1',
        locale: 'en_GH',
        model: 'SM-G998B',
        osVersion: 'Android 14',
        manufacturer: 'samsung',
      );
      expect(gh.localeCountry, 'GH');

      const us = DeviceIdentity(
        deviceId: 'd2',
        platform: 'IOS',
        appVersion: '1.0.0',
        buildNumber: '1',
        locale: 'en-US',
        model: 'iPhone15,2',
        osVersion: 'iOS 17.2',
        manufacturer: 'apple',
      );
      expect(us.localeCountry, 'US');

      const noCountry = DeviceIdentity(
        deviceId: 'd3',
        platform: 'ANDROID',
        appVersion: '1.0.0',
        buildNumber: '1',
        locale: 'en',
        model: 'Pixel 8',
        osVersion: 'Android 14',
        manufacturer: 'Google',
      );
      expect(noCountry.localeCountry, isNull);
    });

    test('DeviceIdentityLoader generates and persists deviceId across loads', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final firstLoad = await DeviceIdentityLoader.load(prefs);
      expect(firstLoad.deviceId, isNotEmpty);
      expect(firstLoad.deviceId, isNot('unknown'));

      final storedId = prefs.getString('lidapay.device_id');
      expect(storedId, firstLoad.deviceId);

      // Second load must reuse existing ID
      final secondLoad = await DeviceIdentityLoader.load(prefs);
      expect(secondLoad.deviceId, firstLoad.deviceId);
    });
  });
}
