import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import 'api_endpoints.dart';
import 'api_exception.dart';
import 'token_store.dart';

/// Centralized Dio client against the live backend. Injects the stored
/// bearer token and transparently refreshes it on 401 (single-flight:
/// concurrent failures share one refresh) before retrying once.
class ApiClient {
  ApiClient({Dio? dio, Dio? refreshDio, required this.tokenStore})
    : _dio = dio ?? _buildDio(),
      _refreshDio = refreshDio ?? _buildDio() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = tokenStore.accessToken;
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          options.headers.putIfAbsent('X-Request-Id', _uuid.v4);
          if (kDebugMode) {
            debugPrint(
              '🌐 API REQUEST[${options.method}] => ${options.uri}'
              '${options.data != null ? ' | body: ${_redact(options.data)}' : ''}',
            );
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          if (kDebugMode) {
            debugPrint(
              '✅ API RESPONSE[${response.statusCode}] => '
              '${response.requestOptions.uri}',
            );
          }
          handler.next(response);
        },
        onError: (error, handler) async {
          if (kDebugMode) {
            debugPrint(
              '❌ API ERROR[${error.response?.statusCode ?? error.type.name}] => '
              '${error.requestOptions.method} ${error.requestOptions.uri} | '
              'response: ${_redact(error.response?.data) ?? error.message}',
            );
          }
          final hadBearer =
              error.requestOptions.headers['Authorization'] != null;
          if (error.response?.statusCode != 401 || !hadBearer) {
            return handler.next(error);
          }
          final options = error.requestOptions;
          if (options.extra['authRetried'] == true) {
            await tokenStore.clear(clearBiometric: true);
            return handler.next(error);
          }
          try {
            final access = await _refreshAccessToken();
            if (access == null) return handler.next(error);
            if (!const ['GET', 'HEAD', 'OPTIONS'].contains(options.method)) {
              return handler.next(error);
            }
            options.extra['authRetried'] = true;
            options.headers['Authorization'] = 'Bearer $access';
            final response = await _dio.fetch<dynamic>(options);
            return handler.resolve(response);
          } on DioException catch (e) {
            return handler.next(e);
          }
        },
      ),
    );
  }

  static const _sensitiveKeys = <String>{
    'password',
    'token',
    'refreshtoken',
    'accesstoken',
    'authorization',
    'secret',
    'otp',
    'pin',
  };

  static Object? _redact(Object? value, [String? key]) {
    if (value == null) return null;
    if (value is Map) {
      return {
        for (final entry in value.entries)
          '${entry.key}': _redact(entry.value, '${entry.key}'),
      };
    }
    if (value is List) {
      return value.map((e) => _redact(e)).toList();
    }
    final k = (key ?? '').toLowerCase();
    if (_sensitiveKeys.any(k.contains) && value is String) {
      return value.length <= 8 ? '***' : '${value.substring(0, 4)}***';
    }
    return value;
  }

  final Dio _dio;
  final Dio _refreshDio;
  final TokenStore tokenStore;

  Future<String?>? _refreshing;

  static const _uuid = Uuid();

  static Dio _buildDio() => Dio(
    BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      // Fail fast on a dead link (common on mobile handovers) but allow slow
      // provider round-trips (Reloadly/Prymo) to finish.
      connectTimeout: AppConstants.apiConnectTimeout,
      sendTimeout: AppConstants.apiConnectTimeout,
      receiveTimeout: AppConstants.apiTimeout,
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    ),
  );

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async => _request(
    () =>
        _dio.get<Map<String, dynamic>>(path, queryParameters: queryParameters),
  );

  /// For endpoints whose response body is not a JSON object
  /// (e.g. GET /users/points returns a bare number).
  Future<dynamic> getRaw(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async => _requestRaw(
    () => _dio.get<dynamic>(path, queryParameters: queryParameters),
  );

  Future<Map<String, dynamic>> post(String path, {Object? body}) async =>
      _request(() => _dio.post<Map<String, dynamic>>(path, data: body));

  /// For POST endpoints whose response body is not a JSON object
  /// (e.g. POST /internet/bundlelist returns a bare array).
  Future<dynamic> postRaw(
    String path, {
    Object? body,
    Map<String, dynamic>? headers,
  }) async => _requestRaw(
    () => _dio.post<dynamic>(
      path,
      data: body,
      options: headers == null ? null : Options(headers: headers),
    ),
  );

  Future<dynamic> putRaw(String path, {Object? body}) async =>
      _requestRaw(() => _dio.put<dynamic>(path, data: body));

  Future<Map<String, dynamic>> put(String path, {Object? body}) async =>
      _request(() => _dio.put<Map<String, dynamic>>(path, data: body));

  Future<Map<String, dynamic>> delete(String path, {Object? body}) async =>
      _request(() => _dio.delete<Map<String, dynamic>>(path, data: body));

  /// DELETE endpoints sometimes answer with a plain acknowledgement string.
  Future<dynamic> deleteRaw(String path, {Object? body}) async =>
      _requestRaw(() => _dio.delete<dynamic>(path, data: body));

  Future<Map<String, dynamic>> _request(
    Future<Response<Map<String, dynamic>>> Function() call,
  ) async {
    final raw = await _requestRaw(
      () => call().then((r) => r as Response<dynamic>),
    );
    if (raw is Map<String, dynamic>) return raw;
    if (raw == null) return <String, dynamic>{};
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<dynamic> _requestRaw(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      return res.data;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<String?> _refreshAccessToken() {
    final pending = _refreshing ??= _doRefresh();
    return pending.whenComplete(() {
      if (identical(_refreshing, pending)) _refreshing = null;
    });
  }

  Future<String?> _doRefresh() async {
    final refreshToken = tokenStore.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      await tokenStore.clear(clearBiometric: true);
      return null;
    }
    try {
      final res = await _refreshDio.post<Map<String, dynamic>>(
        ApiEndpoints.refresh,
        data: {'refreshToken': refreshToken},
      );
      final data = res.data ?? const <String, dynamic>{};
      final access = (data['access_token'] ?? '').toString();
      final next = (data['refresh_token'] ?? '').toString();
      if (access.isEmpty) {
        await tokenStore.clear(clearBiometric: true);
        return null;
      }
      await tokenStore.saveSession(
        accessToken: access,
        refreshToken: next.isEmpty ? null : next,
      );
      return access;
    } on DioException catch (e) {
      // Only an explicit rejection of the refresh token ends the session.
      // Timeouts, offline, and 5xx are transient: keep the tokens so the next
      // request (or app resume) can try again instead of forcing a re-login.
      final code = e.response?.statusCode;
      if (code == 400 || code == 401 || code == 403) {
        await tokenStore.clear(clearBiometric: true);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(tokenStore: ref.watch(tokenStoreProvider));
});
