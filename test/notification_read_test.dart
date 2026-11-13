import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/core/network/token_store.dart';
import 'package:lidapay_app/features/notifications/data/notification_models.dart';
import 'package:lidapay_app/features/notifications/data/notifications_repository.dart';
import 'package:lidapay_app/features/notifications/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CustomTestNotificationsRepo implements NotificationsRepository {
  _CustomTestNotificationsRepo(this.items);

  final List<AppNotification> items;

  @override
  Future<List<AppNotification>> getNotifications() async => items;

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('reading a notification updates unread count and read status instantaneously', () async {
    final now = DateTime.now();
    final items = [
      AppNotification(
        id: 'n1',
        title: 'Top-up 1',
        message: 'Top-up 1 delivered',
        channel: 'push',
        status: 'sent',
        createdAt: now.subtract(const Duration(minutes: 5)),
      ),
      AppNotification(
        id: 'n2',
        title: 'Top-up 2',
        message: 'Top-up 2 delivered',
        channel: 'push',
        status: 'sent',
        createdAt: now.subtract(const Duration(minutes: 15)),
      ),
      AppNotification(
        id: 'n3',
        title: 'Top-up 3',
        message: 'Top-up 3 delivered',
        channel: 'email',
        status: 'sent',
        createdAt: now.subtract(const Duration(minutes: 25)),
      ),
    ];

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        notificationsRepositoryProvider.overrideWithValue(
          _CustomTestNotificationsRepo(items),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Initial load: await the raw notifications
    await container.read(rawNotificationsProvider.future);

    // Initial unread count should be 3
    expect(container.read(unreadNotificationsProvider), 3);
    final initialList = container.read(notificationsProvider).value!;
    expect(initialList.length, 3);
    expect(initialList[0].isRead, isFalse);

    // Mark the first notification as read
    await container
        .read(readNotificationsProvider.notifier)
        .markRead('n1', relatedKeys: ['${items[0].kind}|${items[0].displayMessage}']);

    // Unread count should immediately decrease to 2
    expect(container.read(unreadNotificationsProvider), 2);

    final updatedList = container.read(notificationsProvider).value!;
    expect(updatedList.firstWhere((n) => n.id == 'n1').isRead, isTrue);
    expect(updatedList.firstWhere((n) => n.id == 'n2').isRead, isFalse);

    // Mark all read
    await container.read(readNotificationsProvider.notifier).markAll(['n1', 'n2', 'n3']);

    // Unread count should immediately drop to 0
    expect(container.read(unreadNotificationsProvider), 0);
    final allReadList = container.read(notificationsProvider).value!;
    expect(allReadList.every((n) => n.isRead), isTrue);
  });
}
