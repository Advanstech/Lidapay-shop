import 'dart:async';

import '../../../core/network/api_exception.dart';
import 'auth_models.dart';
import 'auth_repository.dart';

/// Simulated auth backend. Latency + failure injection make loading and
/// error states real.
class MockAuthRepository implements AuthRepository {
  final _latency = const Duration(milliseconds: 800);
  UserProfile? _current;

  @override
  Future<void> register(RegisterRequest request) async {
    await Future<void>.delayed(_latency);
    if (request.email.toLowerCase().contains('taken')) {
      throw const ApiException(
        'An account with this email already exists.',
        code: 'EMAIL_TAKEN',
      );
    }
  }

  @override
  Future<void> registerMerchant(MerchantRegisterRequest request) async {
    await Future<void>.delayed(_latency);
    if (request.email.toLowerCase().contains('taken')) {
      throw const ApiException(
        'An account with this email already exists.',
        code: 'EMAIL_TAKEN',
      );
    }
  }

  @override
  Future<AuthSession> login(LoginRequest request) async {
    await Future<void>.delayed(_latency);
    if (request.password == 'wrongpass') {
      throw const ApiException(
        'Incorrect password. Please try again.',
        code: 'INVALID_CREDENTIALS',
      );
    }
    final username = request.username;
    final name = username.split('@').first;
    _current = UserProfile(
      id: 'usr_demo001',
      firstName: name.isEmpty ? 'Ama' : name,
      lastName: 'Mensah',
      email: username.contains('@') ? username : 'ama.mensah@example.com',
      phoneNumber: '0244588584',
      username: username,
      country: 'GHANA',
      emailVerified: true,
      phoneVerified: false,
      isVerified: true,
    );
    return AuthSession(
      tokens: const AuthTokens(
        accessToken: 'mock-access-token',
        refreshToken: 'mock-refresh',
      ),
      user: _current!,
    );
  }

  @override
  Future<OtpChallengeResponse> requestLoginOtp(
    OtpChallengeRequest request,
  ) async {
    return OtpChallengeResponse(
      challengeToken: 'mock-challenge-${request.username}',
      message: 'Verification code sent to ${request.username}',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<AuthSession> verifyLoginOtp(OtpVerifyRequest request) async {
    if (request.otpCode == '000000' || request.otpCode.length != 6) {
      throw const ApiException(
        'Invalid or expired verification code. Please try again.',
        code: 'INVALID_OTP',
      );
    }
    final username =
        request.username ??
        request.challengeToken.replaceFirst('mock-challenge-', '');
    final name = username.split('@').first;
    _current = UserProfile(
      id: 'usr_demo001',
      firstName: name.isEmpty ? 'Ama' : name,
      lastName: 'Mensah',
      email: username.contains('@') ? username : 'ama.mensah@example.com',
      phoneNumber: '0244588584',
      username: username,
      country: 'GHANA',
      emailVerified: true,
      phoneVerified: true,
      isVerified: true,
    );
    return AuthSession(
      tokens: const AuthTokens(
        accessToken: 'mock-access-token',
        refreshToken: 'mock-refresh',
      ),
      user: _current!,
    );
  }

  @override
  Future<AuthSession?> restoreSession() async => null;

  @override
  Future<UserProfile> getProfile() async {
    // No artificial latency — refreshProfile is fire-and-forget after login
    // and a pending timer at test teardown fails the widget suite.
    return _current ??
        const UserProfile(
          id: 'usr_demo001',
          firstName: 'Ama',
          lastName: 'Mensah',
          email: 'ama.mensah@example.com',
          phoneNumber: '0244588584',
          country: 'GHANA',
          isVerified: true,
        );
  }

  @override
  Future<UserProfile> updateProfile(ProfileUpdateRequest request) async {
    await Future<void>.delayed(_latency);
    final base =
        _current ??
        const UserProfile(
          id: 'usr_demo001',
          firstName: 'Ama',
          lastName: 'Mensah',
          email: 'ama.mensah@example.com',
          phoneNumber: '0244588584',
          country: 'GHANA',
          isVerified: true,
        );
    _current = base.copyWith(
      firstName: request.firstName,
      lastName: request.lastName,
      email: request.email,
      phoneNumber: request.phoneNumber,
    );
    return _current!;
  }

  @override
  Future<void> resendEmailVerification() async {
    await Future<void>.delayed(_latency);
  }

  @override
  Future<void> resendPhoneVerification() async {
    await Future<void>.delayed(_latency);
  }

  @override
  Future<void> confirmPhoneVerification({
    required String phoneNumber,
    required String code,
  }) async {
    await Future<void>.delayed(_latency);
    if (code.length != 6) {
      throw const ApiException('Enter the 6-digit code we sent to your phone.');
    }
    _current = _current?.copyWith(phoneVerified: true);
  }

  @override
  Future<void> requestPasswordReset(String identifier) async {
    await Future<void>.delayed(_latency);
  }

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    await Future<void>.delayed(_latency);
    if (token.isEmpty || newPassword.length < 6) {
      throw const ApiException('This reset link is invalid or has expired.');
    }
  }

  @override
  Future<void> requestPasswordChange({
    required String currentPassword,
    required String newPassword,
  }) async {
    await Future<void>.delayed(_latency);
    if (currentPassword == 'wrongpass') {
      throw const ApiException(
        'Your current password is incorrect.',
        code: 'INVALID_CREDENTIALS',
      );
    }
  }

  @override
  Future<void> confirmPasswordChange({required String token}) async {
    await Future<void>.delayed(_latency);
    if (token.isEmpty) {
      throw const ApiException(
        'This verification link is invalid or has expired.',
      );
    }
  }

  @override
  Future<void> logout() async {}
}
