import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/token_store.dart';
import '../../payments/data/pending_payment.dart';

/// Durable record of an in-flight Lida Value funded top-up.
///
/// For a wallet-funded purchase the debit *is* the payment, so the attempt
/// has to survive process death: without it a killed app can leave the
/// customer's wallet debited with nothing delivered. The persisted
/// [PendingPayment.clientReference] doubles as the idempotency key, so the
/// same purchase retried after a crash reuses it and the backend returns the
/// first result instead of taking the wallet twice.
class LvAttempt {
  const LvAttempt({
    required this.draft,
    required this.serviceType,
    required this.updatedAt,
    this.debitReference,
  });

  /// The purchase being funded, including its idempotency reference.
  final PendingPayment draft;

  /// `AIRTIME` or `DATA` — used to match a retry against this attempt.
  final String serviceType;

  /// The wallet ledger reference — set once the debit is confirmed. A
  /// non-null value means the wallet was already debited and only the
  /// delivery is outstanding.
  final String? debitReference;

  final DateTime updatedAt;

  bool get isDebited => debitReference != null;

  String get recipient => draft.params['recipientNumber']?.toString() ?? '';

  double get amount => draft.deliverAmount;

  /// True when this attempt is the same purchase (recipient, amount and
  /// service) the caller is about to start.
  bool matches({
    required String recipient,
    required double amount,
    required String serviceType,
  }) =>
      this.serviceType == serviceType &&
      this.recipient == recipient &&
      (this.amount - amount).abs() < 0.01;

  Map<String, dynamic> toJson() => {
    'draft': draft.toJson(),
    'serviceType': serviceType,
    if (debitReference != null) 'debitReference': debitReference,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static LvAttempt? fromJson(Map<String, dynamic> json) {
    final draft = json['draft'];
    if (draft is! Map<String, dynamic>) return null;
    try {
      return LvAttempt(
        draft: PendingPayment.fromJson(draft),
        serviceType: json['serviceType'] as String? ?? '',
        debitReference: json['debitReference'] as String?,
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Single-slot persistence for the in-flight wallet-funded purchase.
class LvAttemptStore {
  LvAttemptStore(this._prefs);

  static const _key = 'lidapay.lv_attempt.v1';

  final SharedPreferences _prefs;

  Future<void> save(LvAttempt attempt) =>
      _prefs.setString(_key, jsonEncode(attempt.toJson()));

  LvAttempt? load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return LvAttempt.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() => _prefs.remove(_key);
}

final lvAttemptStoreProvider = Provider<LvAttemptStore>(
  (ref) => LvAttemptStore(ref.watch(sharedPrefsProvider)),
);
