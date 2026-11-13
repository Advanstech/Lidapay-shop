import 'auth_models.dart';

/// Result of a successful login or restored session.
class AuthSession {
  const AuthSession({required this.tokens, required this.user});

  final AuthTokens tokens;
  final UserProfile user;
}

/// Contract for auth. [MockAuthRepository] backs tests and offline demos;
/// [RemoteAuthRepository] is the live implementation over [ApiClient].
abstract class AuthRepository {
  Future<void> register(RegisterRequest request);

  /// POST /api/v1/merchants/register — business account sign-up.
  Future<void> registerMerchant(MerchantRegisterRequest request);

  /// POST /api/v1/users/login — validates credentials and returns the tokens
  /// plus the full user profile in one response.
  Future<AuthSession> login(LoginRequest request);

  /// POST /api/v1/auth/login/request-otp — creates a short-lived login OTP
  /// challenge without creating an authenticated session.
  Future<OtpChallengeResponse> requestLoginOtp(OtpChallengeRequest request);

  /// POST /api/v1/auth/login/verify-otp — verifies the 6-digit OTP against
  /// the active challenge token and returns the authenticated session.
  Future<AuthSession> verifyLoginOtp(OtpVerifyRequest request);

  /// Restores a previously persisted session (tokens + cached profile), or
  /// null when none exists. Only meaningful for live implementations.
  Future<AuthSession?> restoreSession();

  /// GET /api/v1/users/profile — the freshest profile fields. Merged over
  /// the login payload so verification/KYC status stays current.
  Future<UserProfile> getProfile();

  /// PUT /api/v1/users/profile/update — returns the refreshed profile.
  Future<UserProfile> updateProfile(ProfileUpdateRequest request);

  Future<void> resendEmailVerification();

  Future<void> resendPhoneVerification();

  /// POST /api/v1/users/verify-phone — confirms the SMS code sent by
  /// [resendPhoneVerification]. Payload mirrors the legacy contract:
  /// `{phoneNumber, code}`.
  Future<void> confirmPhoneVerification({
    required String phoneNumber,
    required String code,
  });

  /// POST /api/v1/users/reset-password — [identifier] is the account's
  /// email address or phone number; the backend accepts either key.
  Future<void> requestPasswordReset(String identifier);

  /// POST /api/v1/users/confirm-reset-password — the emailed reset link
  /// carries a token; this sets the new password it authorizes.
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  });

  /// PUT /api/v1/users/change-password (Bearer) — starts a signed-in
  /// password change. The backend emails a verification link; the change
  /// only lands once [confirmPasswordChange] accepts its token.
  Future<void> requestPasswordChange({
    required String currentPassword,
    required String newPassword,
  });

  /// POST /api/v1/users/confirm-password-change — completes the emailed
  /// verification link for a signed-in password change.
  Future<void> confirmPasswordChange({required String token});

  Future<void> logout();
}
