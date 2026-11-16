import 'notification_models.dart';

abstract class NotificationsRepository {
  /// GET /api/v1/notifications — every notification for the signed-in user.
  Future<List<AppNotification>> getNotifications();

  /// DELETE /api/v1/notifications/{id}.
  Future<void> deleteNotification(String id);

  /// POST /api/v1/notifications/device-token — registers the FCM token once
  /// push messaging lands; kept behind the repository seam so the screen
  /// layer never talks to Dio directly.
  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    String? deviceId,
    String? appVersion,
    String? locale,
  });

  /// DELETE /api/v1/notifications/device-token — deactivates the device push token
  /// for the currently authenticated user on logout or account switch.
  Future<void> unregisterDeviceToken({required String token});

  /// GET /api/v1/notifications/device-token — returns active token count for
  /// QA/startup verification (`total >= 1` with `isActive: true`).
  Future<int> getActiveDeviceTokenCount();
}
