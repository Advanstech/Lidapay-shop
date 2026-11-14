import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';

/// Mirrors POST /api/v1/users/register (see api/openapi.json).
class RegisterRequest extends Equatable {
  const RegisterRequest({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phoneNumber,
    required this.country,
    required this.password,
  });

  final String firstName;
  final String lastName;
  final String email;
  final String phoneNumber;
  final String country;
  final String password;

  Map<String, dynamic> toJson() => {
    'username': phoneNumber,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'phoneNumber': phoneNumber,
    'mobile': phoneNumber,
    'country': country,
    'password': password,
    'roles': ['user'],
  };

  @override
  List<Object?> get props => [
    firstName,
    lastName,
    email,
    phoneNumber,
    country,
    password,
  ];
}

/// Mirrors POST /api/v1/merchants/register (see api/openapi.json).
class MerchantRegisterRequest extends Equatable {
  const MerchantRegisterRequest({
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.password,
    required this.country,
    this.businessType,
    this.street,
    this.city,
  });

  final String name;
  final String email;
  final String phoneNumber;
  final String password;
  final String country;
  final String? businessType;
  final String? street;
  final String? city;

  Map<String, dynamic> toJson() => {
    'name': name,
    'email': email,
    'phoneNumber': phoneNumber,
    'password': password,
    'country': country,
    if (businessType?.isNotEmpty == true) 'businessType': businessType,
    if (street?.isNotEmpty == true) 'street': street,
    if (city?.isNotEmpty == true) 'city': city,
  };

  @override
  List<Object?> get props => [
    name,
    email,
    phoneNumber,
    password,
    country,
    businessType,
    street,
    city,
  ];
}

/// Mirrors POST /api/v1/users/login — username may be email or phone.
class LoginRequest extends Equatable {
  const LoginRequest({required this.username, required this.password});

  final String username;
  final String password;

  Map<String, dynamic> toJson() => {'username': username, 'password': password};

  @override
  List<Object?> get props => [username, password];
}

/// Request payload for POST /api/v1/auth/login/request-otp.
/// Password is included when requesting an email OTP challenge after password
/// validation, or omitted when requesting a direct account challenge.
class OtpChallengeRequest extends Equatable {
  const OtpChallengeRequest({required this.username});

  final String username;

  Map<String, dynamic> toJson() => {'username': username};

  @override
  List<Object?> get props => [username];
}

/// Challenge returned by POST /api/v1/auth/login/request-otp.
/// Kept only in memory during OTP verification; never persisted as a session.
class OtpChallengeResponse extends Equatable {
  const OtpChallengeResponse({
    required this.challengeToken,
    required this.message,
    this.expiresAt,
  });

  final String challengeToken;
  final String message;
  final DateTime? expiresAt;

  factory OtpChallengeResponse.fromJson(Map<String, dynamic> json) {
    final nested = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    final rawExpiry = (nested['expiresAt'] ?? json['expiresAt'])?.toString();
    return OtpChallengeResponse(
      challengeToken:
          (nested['challengeToken'] ??
                  nested['token'] ??
                  json['challengeToken'] ??
                  '')
              .toString(),
      message:
          (nested['message'] ??
                  json['message'] ??
                  'Verification code sent to your account.')
              .toString(),
      expiresAt: rawExpiry == null ? null : DateTime.tryParse(rawExpiry),
    );
  }

  @override
  List<Object?> get props => [challengeToken, message, expiresAt];
}

/// Request payload for POST /api/v1/auth/login/verify-otp.
class OtpVerifyRequest extends Equatable {
  const OtpVerifyRequest({
    required this.challengeToken,
    required this.otpCode,
    this.username,
    this.deviceToken,
    this.devicePlatform,
    this.deviceId,
    this.appVersion,
    this.locale,
  });

  final String challengeToken;
  final String otpCode;
  final String? username;
  final String? deviceToken;
  final String? devicePlatform;
  final String? deviceId;
  final String? appVersion;
  final String? locale;

  Map<String, dynamic> toJson() => {
    'challengeToken': challengeToken,
    'otpCode': otpCode,
    if (deviceToken != null && deviceToken!.isNotEmpty)
      'deviceToken': deviceToken,
    if (devicePlatform != null && devicePlatform!.isNotEmpty)
      'devicePlatform': devicePlatform,
    if (deviceId != null && deviceId!.isNotEmpty) 'deviceId': deviceId,
    if (appVersion != null && appVersion!.isNotEmpty) 'appVersion': appVersion,
    if (locale != null && locale!.isNotEmpty) 'locale': locale,
  };

  @override
  List<Object?> get props => [
    challengeToken,
    otpCode,
    username,
    deviceToken,
    devicePlatform,
    deviceId,
    appVersion,
    locale,
  ];
}

/// Tokens returned by POST /api/v1/users/login and /api/v1/auth/refresh.
/// Key names match the live API (access_token / refresh_token).
class AuthTokens extends Equatable {
  const AuthTokens({required this.accessToken, this.refreshToken});

  final String accessToken;
  final String? refreshToken;

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    accessToken: (json['access_token'] ?? json['accessToken'] ?? '').toString(),
    refreshToken: (json['refresh_token'] ?? json['refreshToken'])?.toString(),
  );

  @override
  List<Object?> get props => [accessToken, refreshToken];
}

/// Shape of the `user` object in the login response. The swagger schema is
/// loosely typed (NestJS entity not annotated), so fields are defensive.
class UserProfile extends Equatable {
  const UserProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phoneNumber,
    this.username = '',
    this.country = '',
    this.avatar = '',
    this.gravatar = '',
    this.street = '',
    this.city = '',
    this.region = '',
    this.digitalAddress = '',
    this.latitude,
    this.longitude,
    this.emailVerified = false,
    this.phoneVerified = false,
    this.isVerified = false,
    this.kycStatus = 'none',
  });

  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String phoneNumber;
  final String username;
  final String country;
  final String avatar;
  final String gravatar;
  final String street;
  final String city;
  final String region;
  final String digitalAddress;
  final double? latitude;
  final double? longitude;
  final bool emailVerified;
  final bool phoneVerified;
  final bool isVerified;
  final String kycStatus;

  String get fullName => '$firstName $lastName'.trim();

  /// Best number to prefill MoMo wallet fields with. OTP sessions can
  /// carry the account phone in `username` when `phoneNumber` is missing —
  /// callers still validate since `username` may hold an email instead.
  String get contactPhone =>
      phoneNumber.isNotEmpty ? phoneNumber : username;

  /// Resolves the best profile image URL for this user:
  /// 1. Explicit `avatar` or `gravatar` URL from the backend profile payload
  ///    (`data:` URIs are skipped — Image.network can't load them, and the
  ///    computed Gravatar URL below covers the same image anyway)
  /// 2. Standard Gravatar URL computed from the MD5 hash of [email], with
  ///    `d=mp` so users without a Gravatar profile get the default avatar
  ///    instead of a 404 that falls back to the initial letter.
  String? get avatarUrl {
    for (final raw in [avatar, gravatar]) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed == 'null') continue;
      if (trimmed.startsWith('//')) return 'https:$trimmed';
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return trimmed;
      }
    }
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) return null;
    final hash = md5.convert(utf8.encode(cleanEmail)).toString();
    return 'https://www.gravatar.com/avatar/$hash?s=240&d=mp';
  }

  bool get hasDeliveryAddress =>
      street.trim().isNotEmpty && city.trim().isNotEmpty;

  String get formattedDeliveryAddress {
    final parts = [
      street.trim(),
      city.trim(),
      region.trim(),
      country.trim(),
    ].where((s) => s.isNotEmpty).toList();
    return parts.join(', ');
  }

  /// Loosely-typed backend payloads occasionally serialize JS
  /// `undefined`/`null` as literal strings — treat them as missing.
  static String _sane(Object? raw) {
    final s = (raw ?? '').toString().trim();
    return (s == 'undefined' || s == 'null') ? '' : s;
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final addr = json['address'] is Map
        ? Map<String, dynamic>.from(json['address'] as Map)
        : const <String, dynamic>{};
    return UserProfile(
      id: _sane(json['_id'] ?? json['id'] ?? json['userId']),
      firstName: (json['firstName'] ?? '').toString(),
      lastName: (json['lastName'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phoneNumber: _sane(
        json['phoneNumber'] ?? json['phone'] ?? json['username'],
      ),
      username: _sane(json['username']),
      country: (json['country'] ?? addr['country'] ?? '').toString(),
      avatar:
          (json['avatar'] ??
                  json['profileImage'] ??
                  json['photoUrl'] ??
                  json['image'] ??
                  '')
              .toString(),
      gravatar: (json['gravatar'] ?? '').toString(),
      street:
          (json['street'] ??
                  json['addressLine1'] ??
                  addr['street'] ??
                  addr['addressLine1'] ??
                  (json['address'] is String ? json['address'] : '') ??
                  '')
              .toString(),
      city: (json['city'] ?? addr['city'] ?? '').toString(),
      region:
          (json['region'] ??
                  json['state'] ??
                  addr['region'] ??
                  addr['state'] ??
                  '')
              .toString(),
      digitalAddress:
          (json['digitalAddress'] ??
                  json['ghanaPostGps'] ??
                  addr['digitalAddress'] ??
                  '')
              .toString(),
      latitude: _num(json['latitude'] ?? addr['latitude']),
      longitude: _num(json['longitude'] ?? addr['longitude']),
      emailVerified: _flag(json['emailVerified'] ?? json['isEmailVerified']),
      phoneVerified: _flag(json['phoneVerified'] ?? json['isPhoneVerified']),
      isVerified: json['isVerified'] == true || json['status'] == 'ACTIVE',
      kycStatus: (json['kycStatus'] ?? 'none').toString(),
    );
  }

  static bool _flag(dynamic value) => value == true || value == 'true';
  static double? _num(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  UserProfile copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? phoneNumber,
    String? username,
    String? country,
    String? avatar,
    String? gravatar,
    String? street,
    String? city,
    String? region,
    String? digitalAddress,
    double? latitude,
    double? longitude,
    bool? emailVerified,
    bool? phoneVerified,
    bool? isVerified,
  }) => UserProfile(
    id: id,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    email: email ?? this.email,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    username: username ?? this.username,
    country: country ?? this.country,
    avatar: avatar ?? this.avatar,
    gravatar: gravatar ?? this.gravatar,
    street: street ?? this.street,
    city: city ?? this.city,
    region: region ?? this.region,
    digitalAddress: digitalAddress ?? this.digitalAddress,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    emailVerified: emailVerified ?? this.emailVerified,
    phoneVerified: phoneVerified ?? this.phoneVerified,
    isVerified: isVerified ?? this.isVerified,
    kycStatus: kycStatus,
  );

  Map<String, dynamic> toJson() => {
    '_id': id,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'phoneNumber': phoneNumber,
    'username': username,
    'country': country,
    if (avatar.isNotEmpty) 'avatar': avatar,
    if (gravatar.isNotEmpty) 'gravatar': gravatar,
    'street': street,
    'city': city,
    'region': region,
    'digitalAddress': digitalAddress,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    'emailVerified': emailVerified,
    'phoneVerified': phoneVerified,
    'isVerified': isVerified,
    'kycStatus': kycStatus,
  };

  @override
  List<Object?> get props => [
    id,
    firstName,
    lastName,
    email,
    phoneNumber,
    username,
    country,
    avatar,
    gravatar,
    street,
    city,
    region,
    digitalAddress,
    latitude,
    longitude,
    emailVerified,
    phoneVerified,
    isVerified,
    kycStatus,
  ];
}

/// Body of PUT /api/v1/users/profile/update. Only the fields the user is
/// allowed to change are sent — server-managed flags stay server-side.
class ProfileUpdateRequest extends Equatable {
  const ProfileUpdateRequest({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phoneNumber,
    this.street = '',
    this.city = '',
    this.region = '',
    this.country = '',
    this.digitalAddress = '',
    this.latitude,
    this.longitude,
  });

  final String firstName;
  final String lastName;
  final String email;
  final String phoneNumber;
  final String street;
  final String city;
  final String region;
  final String country;
  final String digitalAddress;
  final double? latitude;
  final double? longitude;

  Map<String, dynamic> toJson() => {
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'phoneNumber': phoneNumber,
    if (street.trim().isNotEmpty) 'street': street.trim(),
    if (city.trim().isNotEmpty) 'city': city.trim(),
    if (region.trim().isNotEmpty) 'region': region.trim(),
    if (country.trim().isNotEmpty) 'country': country.trim(),
    if (digitalAddress.trim().isNotEmpty)
      'digitalAddress': digitalAddress.trim(),
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
  };

  @override
  List<Object?> get props => [
    firstName,
    lastName,
    email,
    phoneNumber,
    street,
    city,
    region,
    country,
    digitalAddress,
    latitude,
    longitude,
  ];
}
