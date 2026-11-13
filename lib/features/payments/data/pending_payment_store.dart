import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'pending_payment.dart';

/// Single-slot persistence for the in-flight purchase. The record is written
/// before the checkout URL opens so a process death between initiation and
/// the `lidapay://` return still lets the app verify and credit.
class PendingPaymentStore {
  PendingPaymentStore(this._prefs);

  static const _key = 'lidapay.pending_payment.v1';

  final SharedPreferences _prefs;

  Future<void> save(PendingPayment payment) =>
      _prefs.setString(_key, jsonEncode(payment.toJson()));

  PendingPayment? load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      return PendingPayment.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() => _prefs.remove(_key);
}
