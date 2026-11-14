import 'package:dio/dio.dart';

/// Normalized failure the UI can reason about. Created from Dio errors in
/// [ApiClient]; mock repositories throw these directly.
class ApiException implements Exception {
  const ApiException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    // NestJS default shape: { statusCode, message, error }
    String? message;
    String? code;
    if (data is Map<String, dynamic>) {
      final raw = data['message'];
      message = raw is List ? raw.join(', ') : raw?.toString();
      code = data['error']?.toString();
    }
    return ApiException(
      _friendly(message, e.response?.statusCode) ?? _fallbackFor(e.type),
      code: code,
      statusCode: e.response?.statusCode,
    );
  }

  /// Some backend failures leak internal infrastructure detail (downstream
  /// provider token minting, stack fragments). Translate the opaque ones so
  /// error screens stay actionable instead of parroting internals.
  static String? _friendly(String? message, int? statusCode) {
    final lower = message?.toLowerCase();
    if ((statusCode ?? 0) >= 500 &&
        (lower == null || lower == 'internal server error')) {
      return 'The service is temporarily unavailable. Please try again shortly.';
    }
    if (message == null) {
      return null;
    }
    // Backend auth messages are written for integrators, not customers.
    if (lower!.contains('invalid login identifier')) {
      return 'We couldn\'t find an account with that email or phone number. '
          'Check it and try again, or create an account.';
    }
    if (statusCode == 401 && lower == 'unauthorized') {
      return 'Incorrect phone, email, or password. Please try again.';
    }
    if (lower.contains('access token') || lower.contains('accesstoken')) {
      return 'This service is temporarily unavailable. Please try again shortly.';
    }
    return message;
  }

  static String _fallbackFor(DioExceptionType type) => switch (type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout =>
      'Network timeout. Check your connection and try again.',
    DioExceptionType.connectionError =>
      'No internet connection. You appear to be offline.',
    _ => 'Something went wrong. Please try again.',
  };

  @override
  String toString() => message;
}
