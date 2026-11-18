import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/token_store.dart';
import 'pending_payment.dart';

/// Single-slot persistence for the in-flight purchase. The record is written
/// before the checkout URL opens so a process death between initiation and
/// the `lidapay://` return still lets the app verify and credit.
///
/// The verification [PendingPayment.token] and the payer's MoMo wallet number
/// are the only sensitive fields, so they live in [SecretStore] (Keystore /
/// Keychain) while the rest of the record stays in prefs. [hydrate] must run
/// once at startup so [load] can serve the token synchronously — the same
/// pattern `TokenStore` uses.
class PendingPaymentStore {
  PendingPaymentStore(this._prefs, {SecretStore? secrets})
    : _secrets = secrets ?? MemorySecretStore();

  static const _key = 'lidapay.pending_payment.v1';
  static const _tokenKey = 'lidapay.pending_payment.token';
  static const _momoKey = 'lidapay.pending_payment.momo';

  final SharedPreferences _prefs;
  final SecretStore _secrets;

  String? _token;
  String? _momo;

  /// Reads the encrypted fields into memory and migrates a record written by
  /// an older build, which kept them in plaintext inside the JSON.
  Future<void> hydrate() async {
    try {
      _token = await _secrets.read(_tokenKey);
      _momo = await _secrets.read(_momoKey);
    } catch (_) {
      // A broken keystore degrades to "token unavailable"; the screen then
      // just asks the user to re-check from the pending state.
      return;
    }

    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      var changed = false;
      final legacyToken = json.remove('token');
      final legacyMomo = json.remove('momoNumber');
      if (legacyToken is String && legacyToken.isNotEmpty && _token == null) {
        _token = legacyToken;
        await _secrets.write(_tokenKey, legacyToken);
      }
      if (legacyMomo is String && legacyMomo.isNotEmpty && _momo == null) {
        _momo = legacyMomo;
        await _secrets.write(_momoKey, legacyMomo);
      }
      changed = legacyToken != null || legacyMomo != null;
      if (changed) await _prefs.setString(_key, jsonEncode(json));
    } catch (_) {
      // A corrupt record is treated as no pending purchase by [load].
    }
  }

  Future<void> save(PendingPayment payment) async {
    _token = payment.token;
    _momo = payment.momoNumber;

    final json = payment.toJson();
    var tokenEncrypted = false;
    var momoEncrypted = false;
    try {
      final token = payment.token;
      if (token != null && token.isNotEmpty) {
        await _secrets.write(_tokenKey, token);
        tokenEncrypted = true;
      } else {
        await _secrets.delete(_tokenKey);
      }
      final momo = payment.momoNumber;
      if (momo != null && momo.isNotEmpty) {
        await _secrets.write(_momoKey, momo);
        momoEncrypted = true;
      } else {
        await _secrets.delete(_momoKey);
      }
    } catch (_) {
      // Keystore unavailable: fall back to the previous plaintext shape so
      // the purchase can still be verified instead of being lost.
    }
    if (tokenEncrypted) json.remove('token');
    if (momoEncrypted) json.remove('momoNumber');
    await _prefs.setString(_key, jsonEncode(json));
  }

  PendingPayment? load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final payment = PendingPayment.fromJson(json);
      final token = _token ?? payment.token;
      final momo = _momo ?? payment.momoNumber;
      if (token == payment.token && momo == payment.momoNumber) return payment;
      return payment.copyWith(token: token, momoNumber: momo);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    _token = null;
    _momo = null;
    await _prefs.remove(_key);
    try {
      await _secrets.delete(_tokenKey);
      await _secrets.delete(_momoKey);
    } catch (_) {
      // Nothing sensitive remains in prefs once the record is gone.
    }
  }
}
