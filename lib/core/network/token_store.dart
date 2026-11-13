import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted auth state: tokens plus the last known profile payload.
/// Written on login/refresh, cleared on logout or refresh failure.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main()');
});

/// Overridden in `main()` with a Keystore/Keychain-backed, pre-loaded store.
/// The default (tests, previews) keeps secrets in memory only.
final tokenStoreProvider = Provider<TokenStore>((ref) {
  return TokenStore(ref.watch(sharedPrefsProvider));
});

/// Async key/value backend for secrets.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// In-memory backend — used by tests and as a fallback.
class MemorySecretStore implements SecretStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Android Keystore (EncryptedSharedPreferences successor) / iOS Keychain.
class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              // Never sync tokens to iCloud or restore them onto a new device.
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Tokens and profile live in [SecretStore] (encrypted on device) with a
/// synchronous in-memory mirror so interceptors never await disk I/O.
/// Call [load] once at startup before the first route decision.
class TokenStore {
  TokenStore(this._prefs, {SecretStore? secrets})
    : _secrets = secrets ?? MemorySecretStore() {
    _onClearedController = StreamController<void>.broadcast();
    // Legacy builds kept tokens in plain prefs: seed the mirror so a session
    // survives the upgrade; [load] migrates and wipes the plaintext copies.
    _access = _prefs.getString(_accessKey);
    _refresh = _prefs.getString(_refreshKey);
    _profileRaw = _prefs.getString(_profileKey);
  }

  static const _accessKey = 'lidapay.access_token';
  static const _refreshKey = 'lidapay.refresh_token';
  static const _profileKey = 'lidapay.profile';
  static const _biometricSessionKey = 'lidapay.biometric_session';

  final SharedPreferences _prefs;
  final SecretStore _secrets;
  late final StreamController<void> _onClearedController;

  String? _access;
  String? _refresh;
  String? _profileRaw;

  /// Fires whenever the stored session is invalidated (logout or a rejected
  /// token refresh) so listeners can drop their in-memory session.
  Stream<void> get onCleared => _onClearedController.stream;

  String? get accessToken => _access;
  String? get refreshToken => _refresh;

  bool get hasSession => _access != null && _access!.isNotEmpty;

  Future<bool> get hasBiometricSession async =>
      (await _secrets.read(_biometricSessionKey)) != null;

  Map<String, dynamic>? get profileJson {
    final raw = _profileRaw;
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Loads secrets into memory and migrates any plaintext legacy values.
  /// Never throws: a broken keystore (seen on some OEM ROMs after a restore)
  /// degrades to "signed out" instead of crashing at launch.
  Future<void> load() async {
    try {
      final legacy = {
        _accessKey: _access,
        _refreshKey: _refresh,
        _profileKey: _profileRaw,
      };
      for (final entry in legacy.entries) {
        final value = entry.value;
        if (value != null) {
          await _secrets.write(entry.key, value);
          await _prefs.remove(entry.key);
        }
      }
      _access = await _secrets.read(_accessKey);
      _refresh = await _secrets.read(_refreshKey);
      _profileRaw = await _secrets.read(_profileKey);
    } catch (_) {
      _access = _refresh = _profileRaw = null;
      try {
        await _wipe();
      } catch (_) {}
    }
  }

  Future<void> saveSession({
    required String accessToken,
    String? refreshToken,
    Map<String, dynamic>? profile,
  }) async {
    _access = accessToken;
    await _secrets.write(_accessKey, accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _refresh = refreshToken;
      await _secrets.write(_refreshKey, refreshToken);
    }
    if (profile != null) await saveProfile(profile);
  }

  Future<void> saveProfile(Map<String, dynamic> profile) async {
    _profileRaw = jsonEncode(profile);
    await _secrets.write(_profileKey, _profileRaw!);
  }

  /// Save only the current session material after the user opts into
  /// biometric sign-in. Credentials/passwords are never stored.
  Future<void> saveBiometricSession() async {
    final access = _access;
    final refresh = _refresh;
    if (access == null || access.isEmpty || refresh == null || refresh.isEmpty) {
      throw StateError('A refreshable session is required for biometric sign-in.');
    }
    await _secrets.write(
      _biometricSessionKey,
      jsonEncode({
        'accessToken': access,
        'refreshToken': refresh,
        if (_profileRaw != null) 'profile': jsonDecode(_profileRaw!),
      }),
    );
  }

  Future<bool> restoreBiometricSession() async {
    final raw = await _secrets.read(_biometricSessionKey);
    if (raw == null) return false;
    try {
      final cached = jsonDecode(raw) as Map<String, dynamic>;
      final access = (cached['accessToken'] ?? '').toString();
      final refresh = (cached['refreshToken'] ?? '').toString();
      if (access.isEmpty || refresh.isEmpty) return false;
      await saveSession(
        accessToken: access,
        refreshToken: refresh,
        profile: cached['profile'] is Map
            ? Map<String, dynamic>.from(cached['profile'] as Map)
            : null,
      );
      return true;
    } catch (_) {
      await clearBiometricSession();
      return false;
    }
  }

  Future<void> clearBiometricSession() => _secrets.delete(_biometricSessionKey);

  /// Clears the active login. Explicit logout keeps a separately opted-in
  /// biometric session; rejected tokens must pass [clearBiometric].
  Future<void> clear({bool clearBiometric = false}) async {
    _access = _refresh = _profileRaw = null;
    try {
      await _wipe();
      if (clearBiometric) await clearBiometricSession();
    } finally {
      _onClearedController.add(null);
    }
  }

  Future<void> _wipe() async {
    for (final key in const [_accessKey, _refreshKey, _profileKey]) {
      await _secrets.delete(key);
      await _prefs.remove(key);
    }
  }
}
