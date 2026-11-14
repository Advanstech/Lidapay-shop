import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/token_store.dart';
import 'auth_models.dart';
import 'auth_repository.dart';

/// Live auth against https://api.advansistechnologies.com, shaped by
/// api/openapi.json. Persists tokens + profile via [TokenStore] so the
/// session survives restarts.
class RemoteAuthRepository implements AuthRepository {
  RemoteAuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  @override
  Future<AuthSession> login(LoginRequest request) async {
    final data = await _api.post(ApiEndpoints.login, body: request.toJson());
    return _persistSessionFromJson(data, fallbackUsername: request.username);
  }

  @override
  Future<OtpChallengeResponse> requestLoginOtp(
    OtpChallengeRequest request,
  ) async {
    final data = await _api.post(
      ApiEndpoints.loginRequestOtp,
      body: request.toJson(),
    );
    final challenge = OtpChallengeResponse.fromJson(data);
    if (challenge.challengeToken.isEmpty) {
      throw const ApiException(
        'Could not start verification code challenge. Please try again.',
      );
    }
    return challenge;
  }

  @override
  Future<AuthSession> verifyLoginOtp(OtpVerifyRequest request) async {
    final data = await _api.post(
      ApiEndpoints.loginVerifyOtp,
      body: request.toJson(),
    );
    return _persistSessionFromJson(
      data,
      fallbackUsername: request.username ?? '',
    );
  }

  Future<AuthSession> _persistSessionFromJson(
    Map<String, dynamic> data, {
    required String fallbackUsername,
  }) async {
    final nested = data['data'] is Map
        ? Map<String, dynamic>.from(data['data'] as Map)
        : data;
    final tokens = AuthTokens.fromJson(nested);
    if (tokens.accessToken.isEmpty) {
      throw const ApiException('Sign-in failed. Please try again.');
    }

    final rawUser = nested['user'] ?? data['user'];
    final userJson = rawUser is Map
        ? Map<String, dynamic>.from(rawUser)
        : <String, dynamic>{
            if (fallbackUsername.isNotEmpty) 'username': fallbackUsername,
          };
    _fillUserIdFromJwt(userJson, tokens.accessToken);

    await _tokens.saveSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      profile: userJson,
    );
    return AuthSession(tokens: tokens, user: UserProfile.fromJson(userJson));
  }

  @override
  Future<AuthSession?> restoreSession() async {
    if (!_tokens.hasSession) return null;
    final access = _tokens.accessToken;
    final refresh = _tokens.refreshToken;
    final profileJson = Map<String, dynamic>.from(
      _tokens.profileJson ?? const {},
    );
    if (access == null) return null;
    _fillUserIdFromJwt(profileJson, access);
    final user = UserProfile.fromJson(profileJson);
    // Pre-fix OTP sessions carried sub: "undefined" with no usable user id,
    // which the updated backend now rejects with 401. Evict them at launch.
    if (user.id.isEmpty && _hasInvalidJwtSub(access)) {
      await _tokens.clear(clearBiometric: true);
      return null;
    }
    return AuthSession(
      tokens: AuthTokens(accessToken: access, refreshToken: refresh),
      user: user,
    );
  }

  /// The OTP verify response may omit the `user` object, and sessions saved
  /// before /users/profile ever succeeds lack `_id`. The JWT carries the
  /// same value as `sub` — decode it so downstream providers always have a
  /// usable user id.
  void _fillUserIdFromJwt(Map<String, dynamic> userJson, String accessToken) {
    final existing = (userJson['_id'] ?? userJson['id'] ?? userJson['userId'])
        ?.toString()
        .trim();
    if (existing != null &&
        existing.isNotEmpty &&
        existing != 'undefined' &&
        existing != 'null') {
      return;
    }
    final id = _jwtClaim(accessToken, const ['sub', 'userId', '_id', 'id']);
    if (id != null) userJson['_id'] = id;
  }

  static Map<String, dynamic>? _jwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      payload += '=' * ((4 - payload.length % 4) % 4);
      final decoded = jsonDecode(utf8.decode(base64Decode(payload)));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  static bool _hasInvalidJwtSub(String token) {
    final json = _jwtPayload(token);
    if (json == null) return false;
    final sub = json['sub']?.toString().trim();
    if (sub != 'undefined' && sub != 'null') return false;
    return _jwtClaim(token, const ['sub', 'userId', '_id', 'id']) == null;
  }

  static String? _jwtClaim(String token, List<String> keys) {
    final json = _jwtPayload(token);
    if (json == null) return null;
    for (final key in keys) {
      final value = json[key]?.toString().trim();
      if (value != null &&
          value.isNotEmpty &&
          value != 'undefined' &&
          value != 'null') {
        return value;
      }
    }
    return null;
  }

  @override
  Future<void> register(RegisterRequest request) async {
    await _api.post(ApiEndpoints.register, body: request.toJson());
  }

  @override
  Future<void> registerMerchant(MerchantRegisterRequest request) async {
    await _api.post(ApiEndpoints.merchantRegister, body: request.toJson());
  }

  @override
  Future<UserProfile> getProfile() async {
    final data = await _api.get(ApiEndpoints.profile);
    final current = _tokens.profileJson ?? const <String, dynamic>{};
    final merged = <String, dynamic>{...current, ..._unwrapUser(data)};
    final user = UserProfile.fromJson(merged);
    await _tokens.saveProfile(merged);
    return user;
  }

  @override
  Future<UserProfile> updateProfile(ProfileUpdateRequest request) async {
    final data = await _api.put(
      ApiEndpoints.updateProfile,
      body: request.toJson(),
    );
    final current = _tokens.profileJson ?? const <String, dynamic>{};
    // Merge the submitted KYC/address fields so they persist locally even if
    // the backend response omits optional address properties.
    final merged = <String, dynamic>{
      ...current,
      ...request.toJson(),
      ..._unwrapUser(data),
    };
    final user = UserProfile.fromJson(merged);
    await _tokens.saveProfile(merged);
    return user;
  }

  /// The update endpoint documents CreateUserDto as its response, but some
  /// builds wrap it — accept both a bare user and a `user`/`data` envelope.
  Map<String, dynamic> _unwrapUser(Map<String, dynamic> data) {
    for (final key in const ['user', 'data']) {
      final nested = data[key];
      if (nested is Map) return Map<String, dynamic>.from(nested);
    }
    return data;
  }

  @override
  Future<void> resendEmailVerification() async {
    await _api.post(ApiEndpoints.resendEmailVerification);
  }

  @override
  Future<void> resendPhoneVerification() async {
    await _api.post(ApiEndpoints.resendPhoneVerification);
  }

  @override
  Future<void> confirmPhoneVerification({
    required String phoneNumber,
    required String code,
  }) async {
    await _api.post(
      ApiEndpoints.verifyPhone,
      body: {'phoneNumber': phoneNumber, 'code': code},
    );
  }

  @override
  Future<void> requestPasswordReset(String identifier) async {
    final value = identifier.trim();
    final isPhone = RegExp(r'^\+?\d[\d\s\-()]{5,}$').hasMatch(value);
    await _api.post(
      ApiEndpoints.resetPassword,
      body: isPhone ? {'phoneNumber': value} : {'email': value},
    );
  }

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    await _api.post(
      ApiEndpoints.confirmResetPassword,
      body: {'token': token, 'newPassword': newPassword},
    );
  }

  @override
  Future<void> requestPasswordChange({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _api.put(
      ApiEndpoints.changePassword,
      body: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
    );
  }

  @override
  Future<void> confirmPasswordChange({required String token}) async {
    await _api.post(
      ApiEndpoints.confirmPasswordChange,
      body: {'token': token},
    );
  }

  @override
  Future<void> logout() => _tokens.clear();
}
