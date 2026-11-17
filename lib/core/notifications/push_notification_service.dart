import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../firebase_options.dart';
import '../device/device_identity.dart';
import '../router/app_router.dart';
import '../../features/notifications/providers.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint('Background message handler init warning: $e');
  }
}

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref);
});

class PushNotificationService {
  PushNotificationService(this._ref);

  final Ref _ref;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'lidapay_alerts';
  static const String channelName = 'LidaPay Transactions & Alerts';
  static const String channelDescription =
      'Real-time alerts for top-ups, recipient decisions, payments, and order tracking.';

  bool _initialized = false;
  bool _firebaseAvailable = false;
  String? _lastToken;
  GoRouter? _router;
  bool Function()? _hasSession;
  String? _pendingPayload;

  String? get currentToken => _lastToken;
  bool get isFirebaseAvailable => _firebaseAvailable;

  /// Call once during app startup or shell init.
  Future<void> initialize({
    GoRouter? router,
    bool Function()? hasSession,
  }) async {
    _router = router ?? _router;
    _hasSession = hasSession ?? _hasSession;
    if (_initialized) return;
    _initialized = true;

    // 1. Initialize local notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    try {
      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty && router != null) {
            _handleNotificationPayload(payload, router);
          }
        },
      );

      // Create Android Notification Channel
      final androidImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: channelDescription,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
      }
    } catch (e) {
      debugPrint('Local notifications init non-fatal warning: $e');
    }

    // 2. Initialize Firebase Messaging safely
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _firebaseAvailable = true;

      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Listen for foreground FCM messages and show native heads-up banner
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _showForegroundNotification(message);
      });

      // App opened from background notification
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (router != null) {
          _handleFcmMessage(message, router);
        }
      });

      // Check cold-start notification
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null && router != null) {
        _handleFcmMessage(initialMessage, router);
      }

      // Listen for token updates
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen((newToken) {
        _lastToken = newToken;
        syncDeviceToken();
      });

      // ignore: deprecated_member_use
      _lastToken = await messaging.getToken();
    } catch (e) {
      _firebaseAvailable = false;
      debugPrint('Firebase messaging not configured or unavailable on this host: $e');
    }
  }

  /// Registers the device token with the backend under the active session.
  /// If `getToken()` returned null during early boot, retries fetching it
  /// before bailing out so slow Play Services init still registers on startup.
  Future<void> syncDeviceToken() async {
    var token = _lastToken;
    if ((token == null || token.isEmpty) && _firebaseAvailable) {
      try {
        // ignore: deprecated_member_use
        token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) _lastToken = token;
      } catch (_) {}
    }
    if (token == null || token.isEmpty) return;

    try {
      final identity = _ref.read(deviceIdentityProvider);
      if (identity.deviceId.isEmpty ||
          identity.deviceId.toLowerCase() == 'unknown') {
        return;
      }
      final repo = _ref.read(notificationsRepositoryProvider);
      await repo.registerDeviceToken(
        token: token,
        platform: identity.platform,
        deviceId: identity.deviceId,
        appVersion: identity.appVersion,
        locale: identity.locale,
      );
      debugPrint('Device token registered with backend successfully.');
    } catch (e) {
      debugPrint('Failed to sync device token with backend: $e');
    }
  }

  /// Deactivates token on logout or account switch.
  Future<void> unregisterCurrentToken() async {
    final token = _lastToken;
    if (token == null || token.isEmpty) return;

    try {
      final repo = _ref.read(notificationsRepositoryProvider);
      await repo.unregisterDeviceToken(token: token);
      debugPrint('Device token unregistered on logout.');
    } catch (e) {
      debugPrint('Device token unregister warning: $e');
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    _ref.invalidate(rawNotificationsProvider);
    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString() ?? 'LidaPay';
    final body = notification?.body ?? message.data['body']?.toString() ?? '';
    final payload = jsonEncode(message.data);

    const androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _localNotifications.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  void _handleFcmMessage(RemoteMessage message, GoRouter router) {
    final payload = jsonEncode(message.data);
    handleNotificationPayload(payload, router);
  }

  /// Flushes any cold-start notification payload once an authenticated session
  /// exists so GoRouter does not bounce the user to `/splash` and lose the target.
  void flushPendingNavigation([GoRouter? router]) {
    final pending = _pendingPayload;
    final targetRouter = router ?? _router;
    if (pending == null || targetRouter == null) return;
    if (_hasSession != null && !_hasSession!()) return;
    _pendingPayload = null;
    handleNotificationPayload(pending, targetRouter);
  }

  @visibleForTesting
  void handleNotificationPayload(String rawPayload, GoRouter router) =>
      _handleNotificationPayload(rawPayload, router);

  void _handleNotificationPayload(String rawPayload, GoRouter router) {
    if (_hasSession != null && !_hasSession!()) {
      _pendingPayload = rawPayload;
      return;
    }
    try {
      final data = jsonDecode(rawPayload) as Map<String, dynamic>;
      final notifId =
          data['_id']?.toString() ??
          data['notificationId']?.toString() ??
          data['id']?.toString();
      if (notifId != null && notifId.isNotEmpty) {
        _ref.read(readNotificationsProvider.notifier).markRead(notifId);
      }
      final decisionId = data['decisionId']?.toString();
      if (decisionId != null && decisionId.isNotEmpty) {
        _ref.read(readNotificationsProvider.notifier).markRead(
          'decision_$decisionId',
          relatedKeys: ['decision|$decisionId'],
        );
        router.push(AppRoutes.recipientDecision(decisionId));
        return;
      }

      final orderId = data['orderId']?.toString() ?? data['shopOrderId']?.toString();
      if (orderId != null && orderId.isNotEmpty) {
        router.push('/shop/orders/$orderId');
        return;
      }

      final type = data['type']?.toString() ?? data['eventType']?.toString();
      if (type == 'recipient_decision' || type == 'recipient_topup_decision') {
        final id = data['decisionId']?.toString();
        if (id != null) {
          router.push(AppRoutes.recipientDecision(id));
          return;
        }
      }

      // Default fallback: open in-app notifications hub
      router.push(AppRoutes.notifications);
    } catch (e) {
      debugPrint('Failed to parse notification payload: $e');
    }
  }
}
