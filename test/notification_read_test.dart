import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/core/network/token_store.dart';
import 'package:lidapay_app/features/auth/data/auth_models.dart';
import 'package:lidapay_app/features/notifications/data/notification_models.dart';
import 'package:lidapay_app/features/notifications/data/notifications_repository.dart';
import 'package:lidapay_app/features/notifications/providers.dart';
import 'package:lidapay_app/features/notifications/screens/notifications_screen.dart';
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

  @override
  Future<int> getActiveDeviceTokenCount() async => 1;
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

  test('marking one notification with duplicate message (>10 min apart) decrements count by 1 while merging <10 min channel duplicates', () async {
    final now = DateTime.now();
    final items = [
      // Same card (email + push within 5 minutes of each other)
      AppNotification(
        id: 'n1_email',
        title: 'Profile updated',
        message: 'Your profile has been updated successfully.',
        channel: 'email',
        status: 'sent',
        kind: 'security',
        createdAt: now.subtract(const Duration(minutes: 2)),
      ),
      AppNotification(
        id: 'n1_push',
        title: 'Profile updated',
        message: 'Your profile has been updated successfully.',
        channel: 'push',
        status: 'sent',
        kind: 'security',
        createdAt: now.subtract(const Duration(minutes: 4)),
      ),
      // Separate older notification with identical text (> 10 min apart)
      AppNotification(
        id: 'n2_older',
        title: 'Profile updated',
        message: 'Your profile has been updated successfully.',
        channel: 'push',
        status: 'sent',
        kind: 'security',
        createdAt: now.subtract(const Duration(minutes: 45)),
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

    await container.read(rawNotificationsProvider.future);

    // 2 visible cards (the email/push pair merged, older kept separate)
    final list = container.read(notificationsProvider).value!;
    expect(list.length, 2);
    expect(list.first.mergedIds, containsAll(['n1_email', 'n1_push']));
    expect(container.read(unreadNotificationsProvider), 2);

    // Marking the first card reads both merged IDs without marking the older duplicate
    await container.read(readNotificationsProvider.notifier).markRead(
      list.first.id,
      relatedKeys: list.first.mergedIds,
    );

    expect(container.read(unreadNotificationsProvider), 1);
    final after = container.read(notificationsProvider).value!;
    expect(after.firstWhere((n) => n.id == 'n1_push').isRead, isTrue);
    expect(after.firstWhere((n) => n.id == 'n2_older').isRead, isFalse);
  });

  test('belongsToUser scopes notifications to matching user id, email, or phone', () {
    const user = UserProfile(
      id: 'user-123',
      firstName: 'Kofi',
      lastName: 'Mensah',
      email: 'Kofi@Example.com',
      phoneNumber: '0244588584',
      username: '0244588584',
    );
    final now = DateTime.now();

    AppNotification makeWithUser(String? target) => AppNotification(
      id: 'id_$target',
      title: 'Alert',
      message: 'Test',
      channel: 'push',
      status: 'sent',
      createdAt: now,
      userId: target,
    );

    expect(makeWithUser('user-123').belongsToUser(user), isTrue);
    expect(makeWithUser('kofi@example.com').belongsToUser(user), isTrue);
    expect(makeWithUser('0244588584').belongsToUser(user), isTrue);
    expect(makeWithUser('+233244588584').belongsToUser(user), isTrue);
    expect(makeWithUser('233 244 588 584').belongsToUser(user), isTrue);
    expect(makeWithUser(null).belongsToUser(user), isTrue);
    expect(makeWithUser('').belongsToUser(user), isTrue);

    expect(makeWithUser('other-user-999').belongsToUser(user), isFalse);
    expect(makeWithUser('other@example.com').belongsToUser(user), isFalse);
    expect(makeWithUser('0559998888').belongsToUser(user), isFalse);
  });

  testWidgets('tapping a notification opens detail sheet as READ and decrements unread count immediately', (tester) async {
    final now = DateTime.now();
    final items = [
      AppNotification(
        id: 'notif-1',
        title: 'Airtime Top-Up',
        message: 'Airtime delivered to 0244588584',
        channel: 'push',
        status: 'sent',
        kind: 'airtime',
        createdAt: now.subtract(const Duration(minutes: 5)),
      ),
      AppNotification(
        id: 'notif-2',
        title: 'Airtime Top-Up',
        message: 'Airtime delivered to 0244588584',
        channel: 'push',
        status: 'sent',
        kind: 'airtime',
        createdAt: now.subtract(const Duration(minutes: 30)),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          notificationsRepositoryProvider.overrideWithValue(
            _CustomTestNotificationsRepo(items),
          ),
        ],
        child: const MaterialApp(home: NotificationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 unread'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotificationsScreen)),
    );
    expect(container.read(unreadNotificationsProvider), 2);

    await tester.tap(find.byKey(const ValueKey('notification_notif-1')));
    await tester.pumpAndSettle();

    expect(find.text('READ'), findsOneWidget);
    expect(find.text('1 unread'), findsOneWidget);
    expect(container.read(unreadNotificationsProvider), 1);
  });
}
