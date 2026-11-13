import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/token_store.dart';
import 'legal_content.dart';

/// Versioned record of the policies a user accepted. Persisted locally so
/// enforcement works offline; a version bump on [kCurrentPolicyVersion]
/// flips [policyStatusProvider] back to pending for every account on the
/// device until they re-accept.
class PolicyAcceptance {
  const PolicyAcceptance({required this.version, required this.acceptedAt});

  final int version;
  final DateTime acceptedAt;

  bool get isCurrent => version >= kCurrentPolicyVersion;
}

final policyStatusProvider =
    AsyncNotifierProvider<PolicyStatusNotifier, PolicyAcceptance?>(
      PolicyStatusNotifier.new,
    );

class PolicyStatusNotifier extends AsyncNotifier<PolicyAcceptance?> {
  static const _versionKey = 'policy_accepted_version';
  static const _acceptedAtKey = 'policy_accepted_at';

  @override
  Future<PolicyAcceptance?> build() async {
    final prefs = ref.watch(sharedPrefsProvider);
    final version = prefs.getInt(_versionKey);
    if (version == null) return null;
    final millis = prefs.getInt(_acceptedAtKey) ?? 0;
    return PolicyAcceptance(
      version: version,
      acceptedAt: DateTime.fromMillisecondsSinceEpoch(millis),
    );
  }

  /// Persists acceptance of [kCurrentPolicyVersion]. Called from the
  /// registration gate and the legal review card.
  Future<void> accept() async {
    final prefs = ref.read(sharedPrefsProvider);
    final now = DateTime.now();
    await prefs.setInt(_versionKey, kCurrentPolicyVersion);
    await prefs.setInt(_acceptedAtKey, now.millisecondsSinceEpoch);
    state = AsyncData(
      PolicyAcceptance(version: kCurrentPolicyVersion, acceptedAt: now),
    );
  }
}

/// Direct SharedPreferences read for places that can't await a provider
/// (e.g. synchronous gating inside form validation).
bool policyAcceptedSync(SharedPreferences prefs) {
  return (prefs.getInt(PolicyStatusNotifier._versionKey) ?? 0) >=
      kCurrentPolicyVersion;
}
