import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/core/network/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FailingSecretStore implements SecretStore {
  @override
  Future<void> delete(String key) async => throw Exception('Disk error');

  @override
  Future<String?> read(String key) async => throw Exception('Keystore corrupted');

  @override
  Future<void> write(String key, String value) async =>
      throw Exception('Write failed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TokenStore', () {
    test('saveSession updates memory mirror and writes to secret store', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secrets = MemorySecretStore();
      final store = TokenStore(prefs, secrets: secrets);

      expect(store.hasSession, isFalse);
      expect(store.accessToken, isNull);

      await store.saveSession(
        accessToken: 'access_123',
        refreshToken: 'refresh_456',
        profile: {'id': 'user_1', 'phone': '0244588584'},
      );

      expect(store.hasSession, isTrue);
      expect(store.accessToken, 'access_123');
      expect(store.refreshToken, 'refresh_456');
      expect(store.profileJson?['phone'], '0244588584');

      // Verify secrets store holds values
      expect(await secrets.read('lidapay.access_token'), 'access_123');
      expect(await secrets.read('lidapay.refresh_token'), 'refresh_456');
    });

    test('legacy migration moves plaintext tokens from SharedPreferences to SecretStore', () async {
      SharedPreferences.setMockInitialValues({
        'lidapay.access_token': 'legacy_access',
        'lidapay.refresh_token': 'legacy_refresh',
        'lidapay.profile': '{"name":"Legacy User"}',
      });
      final prefs = await SharedPreferences.getInstance();
      final secrets = MemorySecretStore();

      final store = TokenStore(prefs, secrets: secrets);
      // Synchronous mirror read legacy at construct time
      expect(store.accessToken, 'legacy_access');

      await store.load();

      // Secrets now holds the migrated values
      expect(await secrets.read('lidapay.access_token'), 'legacy_access');
      expect(await secrets.read('lidapay.refresh_token'), 'legacy_refresh');
      expect(store.profileJson?['name'], 'Legacy User');

      // Legacy plaintext prefs must be wiped
      expect(prefs.getString('lidapay.access_token'), isNull);
      expect(prefs.getString('lidapay.refresh_token'), isNull);
      expect(prefs.getString('lidapay.profile'), isNull);
    });

    test('clear wipes in-memory tokens and fires onCleared stream', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secrets = MemorySecretStore();
      final store = TokenStore(prefs, secrets: secrets);

      await store.saveSession(accessToken: 'token_abc');
      expect(store.hasSession, isTrue);

      var onClearedFired = false;
      final sub = store.onCleared.listen((_) => onClearedFired = true);

      await store.clear();
      await pumpEventQueue();

      expect(store.hasSession, isFalse);
      expect(store.accessToken, isNull);
      expect(onClearedFired, isTrue);
      expect(await secrets.read('lidapay.access_token'), isNull);

      await sub.cancel();
    });

    test('biometric session survives logout and restores only after unlock', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secrets = MemorySecretStore();
      final store = TokenStore(prefs, secrets: secrets);

      await store.saveSession(
        accessToken: 'access_123',
        refreshToken: 'refresh_456',
        profile: {'id': 'user_1'},
      );
      await store.saveBiometricSession();
      await store.clear();

      expect(store.hasSession, isFalse);
      expect(await store.hasBiometricSession, isTrue);
      expect(await store.restoreBiometricSession(), isTrue);
      expect(store.accessToken, 'access_123');
      expect(store.refreshToken, 'refresh_456');
      expect(store.profileJson?['id'], 'user_1');
    });

    test('token refresh keeps the biometric snapshot in sync', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = TokenStore(prefs, secrets: MemorySecretStore());

      await store.saveSession(
        accessToken: 'access_1',
        refreshToken: 'refresh_1',
      );
      await store.saveBiometricSession();

      // Server rotates tokens on refresh — the stored biometric snapshot
      // must track the new pair or fingerprint sign-in dies on first use.
      await store.saveSession(
        accessToken: 'access_2',
        refreshToken: 'refresh_2',
      );
      await store.clear();

      expect(await store.restoreBiometricSession(), isTrue);
      expect(store.accessToken, 'access_2');
      expect(store.refreshToken, 'refresh_2');
    });

    test('rejected session can remove the biometric credential', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = TokenStore(prefs, secrets: MemorySecretStore());

      await store.saveSession(
        accessToken: 'access_123',
        refreshToken: 'refresh_456',
      );
      await store.saveBiometricSession();
      await store.clear(clearBiometric: true);

      expect(await store.hasBiometricSession, isFalse);
      expect(await store.restoreBiometricSession(), isFalse);
    });

    test('corrupted secret store degrades gracefully to signed-out without crashing', () async {
      SharedPreferences.setMockInitialValues({
        'lidapay.access_token': 'test_token',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = TokenStore(prefs, secrets: FailingSecretStore());

      // Must not throw
      await store.load();
      expect(store.hasSession, isFalse);
      expect(store.accessToken, isNull);
    });
  });
}
