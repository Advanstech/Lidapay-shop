import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_payload.dart';
import 'notification_models.dart';
import 'notifications_repository.dart';

/// Live notification store over /api/v1/notifications. The list endpoint
/// returns a bare array in the spec example, but `rowsOf` also covers the
/// wrapped shapes this backend emits elsewhere.
class RemoteNotificationsRepository implements NotificationsRepository {
  RemoteNotificationsRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<AppNotification>> getNotifications() async {
    final raw = await _api.getRaw(ApiEndpoints.notifications);
    final items = rowsOf(raw)
        .map(AppNotification.fromApiJson)
        .where((n) => n.id.isNotEmpty)
        .toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Future<void> deleteNotification(String id) {
    return _api.deleteRaw(ApiEndpoints.notification(id));
  }

  @override
  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    String? deviceId,
    String? appVersion,
    String? locale,
  }) {
    return _api.postRaw(
      ApiEndpoints.deviceToken,
      body: {
        'token': token,
        'platform': platform,
        'provider': 'FCM',
        'deviceId': ?deviceId,
        'appVersion': ?appVersion,
        'locale': ?locale,
      },
    );
  }

  @override
  Future<void> unregisterDeviceToken({required String token}) {
    return _api.deleteRaw(
      ApiEndpoints.deviceToken,
      body: {'token': token},
    );
  }

  @override
  Future<int> getActiveDeviceTokenCount() async {
    final raw = await _api.getRaw(ApiEndpoints.deviceToken);
    final pool = payloadPool(asMap(raw));
    final tokens = pool['tokens'];
    if (tokens is List) {
      return tokens
          .whereType<Map>()
          .where((item) => item['isActive'] != false)
          .length;
    }
    return numberField(pool, const ['total', 'count'])?.toInt() ?? 0;
  }
}
