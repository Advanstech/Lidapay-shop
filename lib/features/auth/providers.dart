import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/device_identity.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/token_store.dart';
import '../../core/notifications/push_notification_service.dart';
import 'data/auth_models.dart';
import 'data/auth_repository.dart';
import 'data/remote_auth_repository.dart';

/// One-line swap point between the mock backend and the live API.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return RemoteAuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStoreProvider),
  );
});

/// Current session; null when logged out.
final authSessionProvider = StateNotifierProvider<AuthNotifier, AuthSession?>((
  ref,
) {
  return AuthNotifier(
    ref.watch(authRepositoryProvider),
    ref.watch(tokenStoreProvider),
    deviceIdentity: ref.watch(deviceIdentityProvider),
    onAuthenticated: () =>
        ref.read(pushNotificationServiceProvider).syncDeviceToken(),
    onLoggingOut: () =>
        ref.read(pushNotificationServiceProvider).unregisterCurrentToken(),
  );
});

/// Booleans out of the session for the router: profile edits replace the
/// session object but must not recreate [GoRouter].
final hasSessionProvider = Provider<bool>((ref) {
  return ref.watch(authSessionProvider.select((session) => session != null));
});

/// Watched by screens that need the freshest profile fields (Profile,
/// Edit Profile). Fires a best-effort GET /users/profile once per mount.
final profileSyncProvider = FutureProvider<void>((ref) {
  return ref.read(authSessionProvider.notifier).refreshProfile();
});

class AuthNotifier extends StateNotifier<AuthSession?> {
  AuthNotifier(
    this._repository,
    this._tokens, {
    this.deviceIdentity,
    this.onAuthenticated,
    this.onLoggingOut,
  }) : super(null) {
    // A failed token refresh clears the store mid-session; mirror that here
    // so the router drops the user back on the login screen.
    _clearedSub = _tokens.onCleared.listen((_) => state = null);
  }

  final AuthRepository _repository;
  final TokenStore _tokens;
  final DeviceIdentity? deviceIdentity;
  final Future<void> Function()? onAuthenticated;
  final Future<void> Function()? onLoggingOut;

  StreamSubscription<void>? _clearedSub;
  OtpChallengeResponse? _pendingOtpChallenge;
  String? _pendingOtpUsername;
  DateTime? _emailVerificationSentAt;
  bool _didAttemptRestore = false;

  /// Whether cold-start session restoration has already run for this notifier.
  bool get didAttemptRestore => _didAttemptRestore;

  /// The resend endpoint is rate-limited; block repeat taps inside this
  /// window so they never reach the API (the backend enforces its own
  /// limit across app restarts).
  static const _emailVerificationCooldown = Duration(seconds: 60);

  OtpChallengeResponse? get pendingOtpChallenge => _pendingOtpChallenge;

  /// POST /api/v1/users/login — one request returns the session.
  Future<void> login(LoginRequest request) async {
    state = await _repository.login(request);
    _pendingOtpChallenge = null;
    _pendingOtpUsername = null;
    unawaited(refreshProfile());
    if (onAuthenticated != null) {
      unawaited(onAuthenticated!());
    }
  }

  /// POST /api/v1/auth/login/request-otp — public call; the contract sends
  /// `{username}` only, never a password or token. Stores the returned
  /// challenge in memory only.
  Future<OtpChallengeResponse> requestLoginOtp({
    required String username,
  }) async {
    final challenge = await _repository.requestLoginOtp(
      OtpChallengeRequest(username: username),
    );
    _pendingOtpChallenge = challenge;
    _pendingOtpUsername = username;
    return challenge;
  }

  /// POST /api/v1/auth/login/verify-otp — verifies 6-digit code and saves session.
  Future<void> verifyLoginOtp({
    required String username,
    required String otpCode,
    String? challengeToken,
  }) async {
    final token =
        challengeToken ??
        (_pendingOtpUsername == username
            ? _pendingOtpChallenge?.challengeToken
            : null);
    if (token == null || token.isEmpty) {
      throw const ApiException(
        'Please request a verification code first or sign in with your password.',
      );
    }
    final identity = deviceIdentity;
    state = await _repository.verifyLoginOtp(
      OtpVerifyRequest(
        challengeToken: token,
        otpCode: otpCode,
        username: username,
        deviceId: identity?.deviceId,
        devicePlatform: identity?.platform,
        appVersion: identity?.appVersion,
        locale: identity?.locale,
      ),
    );
    _pendingOtpChallenge = null;
    _pendingOtpUsername = null;
    // The verify payload may omit the user object — fill the profile before
    // navigation so downstream providers (wallet, transactions) see a real
    // user id instead of racing the fire-and-forget refresh.
    try {
      await refreshProfile();
    } catch (_) {
      // Best-effort: a failed fetch retries once in the background.
    }
    if (onAuthenticated != null) {
      unawaited(onAuthenticated!());
    }
  }

  Future<void> verifyOtp(String username, String code) =>
      verifyLoginOtp(username: username, otpCode: code);

  Future<OtpChallengeResponse> resendOtp(String username) =>
      requestLoginOtp(username: username);

  /// Restores a persisted session at cold start.
  Future<void> restore() async {
    _didAttemptRestore = true;
    if (state != null) return;
    state = await _repository.restoreSession();
    if (state != null && onAuthenticated != null) {
      unawaited(onAuthenticated!());
    }
    unawaited(refreshProfile());
  }

  Future<bool> get hasBiometricLogin => _tokens.hasBiometricSession;

  Future<void> enableBiometricLogin() => _tokens.saveBiometricSession();

  Future<void> biometricLogin() async {
    if (!await _tokens.restoreBiometricSession()) {
      throw const ApiException(
        'Biometric sign-in is not set up. Sign in with your password first.',
      );
    }
    final session = await _repository.restoreSession();
    if (session == null) {
      await _tokens.clear(clearBiometric: true);
      throw const ApiException(
        'Biometric sign-in expired. Sign in with your password again.',
      );
    }
    state = session;
    if (onAuthenticated != null) unawaited(onAuthenticated!());
    unawaited(refreshProfile());
  }

  /// GET /api/v1/users/profile — refreshes display fields (names,
  /// verification, KYC) without touching the tokens. Best-effort: a failed
  /// fetch keeps the cached profile. Transient failures (the backend throws
  /// occasional 5xx) get one delayed retry; auth failures do not.
  Future<void> refreshProfile() => _refreshProfile(attempt: 0);

  Future<void> _refreshProfile({required int attempt}) async {
    final session = state;
    if (session == null) return;
    try {
      final user = await _repository.getProfile();
      if (mounted && state != null) {
        state = AuthSession(tokens: session.tokens, user: user);
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401 && mounted) {
        await _tokens.clear(clearBiometric: true);
        if (mounted) state = null;
        return;
      }
      if (attempt == 0 &&
          e.statusCode != 401 &&
          e.statusCode != 403 &&
          mounted) {
        unawaited(
          Future<void>.delayed(
            const Duration(seconds: 2),
            () => _refreshProfile(attempt: 1),
          ),
        );
      }
      // Cached profile stays.
    } catch (_) {
      // Cached profile stays.
    }
  }

  Future<void> register(RegisterRequest request) =>
      _repository.register(request);

  Future<void> registerMerchant(MerchantRegisterRequest request) =>
      _repository.registerMerchant(request);

  /// PUT /api/v1/users/profile/update — keeps the current tokens.
  Future<UserProfile> updateProfile(ProfileUpdateRequest request) async {
    final session = state;
    if (session == null) {
      throw const ApiException('Your session expired. Please sign in again.');
    }
    final user = await _repository.updateProfile(request);
    if (mounted && state != null) {
      state = AuthSession(tokens: session.tokens, user: user);
    }
    return user;
  }

  Future<void> resendEmailVerification() async {
    final last = _emailVerificationSentAt;
    if (last != null) {
      final wait =
          _emailVerificationCooldown - DateTime.now().difference(last);
      if (wait > Duration.zero) {
        throw ApiException(
          'Verification email was just sent. Please wait ${wait.inSeconds}s '
          'before requesting another.',
        );
      }
    }
    await _repository.resendEmailVerification();
    _emailVerificationSentAt = DateTime.now();
  }

  Future<void> resendPhoneVerification() =>
      _repository.resendPhoneVerification();

  /// POST /api/v1/users/verify-phone, then refreshes the profile so the
  /// verified flag lands everywhere it is displayed.
  Future<void> confirmPhoneVerification({
    required String phoneNumber,
    required String code,
  }) async {
    await _repository.confirmPhoneVerification(
      phoneNumber: phoneNumber,
      code: code,
    );
    await refreshProfile();
  }

  Future<void> requestPasswordReset(String identifier) =>
      _repository.requestPasswordReset(identifier);

  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) => _repository.confirmPasswordReset(
    token: token,
    newPassword: newPassword,
  );

  /// PUT /api/v1/users/change-password — emails a verification link; the
  /// change lands only after the link's token is confirmed.
  Future<void> requestPasswordChange({
    required String currentPassword,
    required String newPassword,
  }) => _repository.requestPasswordChange(
    currentPassword: currentPassword,
    newPassword: newPassword,
  );

  Future<void> confirmPasswordChange({required String token}) =>
      _repository.confirmPasswordChange(token: token);

  Future<void> logout() async {
    try {
      if (onLoggingOut != null) {
        await onLoggingOut!();
      }
    } catch (_) {}
    await _repository.logout();
    state = null;
  }

  @override
  void dispose() {
    _clearedSub?.cancel();
    super.dispose();
  }
}
