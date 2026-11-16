import 'notification_models.dart';
import 'notifications_repository.dart';

class MockNotificationsRepository implements NotificationsRepository {
  // No artificial latency — the dashboard bell watches this provider and a
  // pending timer at test teardown fails the widget suite.
  @override
  Future<List<AppNotification>> getNotifications() async {
    final now = DateTime.now();
    return [
      AppNotification(
        id: 'n1',
        title: 'Airtime delivered',
        message: 'Your MTN airtime top-up of GH₵50.00 to 0244 588 584 was delivered successfully.',
        channel: 'push',
        status: 'sent',
        kind: 'airtime',
        createdAt: now.subtract(const Duration(minutes: 24)),
      ),
      AppNotification(
        id: 'n2',
        title: 'Order shipped',
        message: 'Your Lidapay Shop order ORD-22115 (Samsung Galaxy A05) is on its way. Track it in Shop → Orders.',
        channel: 'push',
        status: 'sent',
        kind: 'order',
        createdAt: now.subtract(const Duration(hours: 3)),
      ),
      AppNotification(
        id: 'n3',
        title: 'Lida Value received',
        message: 'Kofi sent you 25.00 LV. It is available in your Lida Value wallet now.',
        channel: 'in_app',
        status: 'sent',
        kind: 'wallet',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      AppNotification(
        id: 'n4',
        title: 'Security check',
        message: 'A new device signed in to your Lidapay account. If this wasn\'t you, change your password immediately.',
        channel: 'email',
        status: 'sent',
        kind: 'security',
        createdAt: now.subtract(const Duration(days: 2, hours: 5)),
      ),
      AppNotification(
        id: 'n5',
        title: 'Weekend flash deals',
        message: 'Up to 20% off Samsung, Oraimo and Melcom picks — ends Sunday at midnight.',
        channel: 'push',
        status: 'sent',
        kind: 'promo',
        createdAt: now.subtract(const Duration(days: 4)),
      ),
    ];
  }

  @override
  Future<void> deleteNotification(String id) async {}

  @override
  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    String? deviceId,
    String? appVersion,
    String? locale,
  }) async {}

  @override
  Future<void> unregisterDeviceToken({required String token}) async {}

  @override
  Future<int> getActiveDeviceTokenCount() async => 1;
}
