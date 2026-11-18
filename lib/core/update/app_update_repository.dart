import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import 'app_update_models.dart';

/// Source of the app-version policy that drives the update gate.
///
/// Implementations must never throw: the gate ships enabled in production and
/// a failing version check cannot be allowed to break app start.
abstract class AppUpdateRepository {
  Future<AppVersionPolicy> fetchPolicy({
    required String platform,
    required String appVersion,
    required int buildNumber,
  });
}

/// Used by tests and by the web/desktop builds, where the Play update flow
/// does not exist.
class NoopAppUpdateRepository implements AppUpdateRepository {
  const NoopAppUpdateRepository();

  @override
  Future<AppVersionPolicy> fetchPolicy({
    required String platform,
    required String appVersion,
    required int buildNumber,
  }) async => AppVersionPolicy.none;
}

/// Reads `GET /api/v1/app/version` and parses it into [AppVersionPolicy].
///
/// Unauthenticated by design: Google Play may already have blocked the old
/// build, so the gate has to work before sign-in. Every failure mode (offline,
/// 404 from a backend that has not shipped the route, bad payload, timeout)
/// resolves to [AppVersionPolicy.none]; the gate then does nothing.
class RemoteAppUpdateRepository implements AppUpdateRepository {
  RemoteAppUpdateRepository(
    this._client, {
    String? path,
    this.timeout = const Duration(seconds: 6),
  }) : _path = path ?? ApiEndpoints.appVersionPolicy;

  final ApiClient _client;
  final String _path;

  /// Short on purpose: a version check must not delay the first frame.
  final Duration timeout;

  AppVersionPolicy? _cached;

  @override
  Future<AppVersionPolicy> fetchPolicy({
    required String platform,
    required String appVersion,
    required int buildNumber,
  }) async {
    final cached = _cached;
    if (cached != null) return cached;

    try {
      final raw = await _client
          .getRaw(
            _path,
            queryParameters: {
              'platform': platform,
              'version': appVersion,
              'build': buildNumber,
            },
          )
          .timeout(timeout);
      if (raw is! Map) return AppVersionPolicy.none;
      final policy = AppVersionPolicy.fromApiJson(
        Map<String, dynamic>.from(raw),
        platform: platform,
      );
      _cached = policy;
      return policy;
    } catch (_) {
      // Fail open, and do not cache: the next launch (or resume) retries.
      return AppVersionPolicy.none;
    }
  }
}
