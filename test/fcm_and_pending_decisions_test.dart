import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/core/device/device_identity.dart';
import 'package:lidapay_app/core/network/api_client.dart';
import 'package:lidapay_app/core/network/token_store.dart';
import 'package:lidapay_app/features/auth/data/auth_models.dart';
import 'package:lidapay_app/features/notifications/data/remote_notifications_repository.dart';
import 'package:lidapay_app/features/recipient_choice/data/recipient_choice_repository.dart';
import 'package:lidapay_app/features/recipient_choice/data/recipient_models.dart';
import 'package:lidapay_app/features/recipient_choice/data/remote_recipient_choice_repository.dart';
import 'package:lidapay_app/features/recipient_choice/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(String json, {int status = 200}) =>
    ResponseBody.fromString(
      json,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

class _FakePendingRepo implements RecipientChoiceRepository {
  _FakePendingRepo(this.items);

  final List<RecipientDecision> items;

  @override
  Future<List<RecipientDecision>> getPendingDecisions() async => items;

  @override
  Future<RecipientEligibility> checkEligibility({
    required String recipientPhone,
    required String serviceType,
    String? countryIsoCode,
  }) async => const RecipientEligibility.unregistered();

  @override
  Future<RecipientDecision> getDecision(String decisionId) async => items.first;

  @override
  Future<RecipientDecision> respondToDecision({
    required String decisionId,
    required RecipientChoice choice,
    required String idempotencyKey,
  }) async => items.first;

  @override
  Future<TopupOrderStatus> getTopupStatus(String topupOrderId) async =>
      TopupOrderStatus(topupOrderId: topupOrderId, state: TopupState.pending);
}

void main() {
  group('Auth request device metadata', () {
    test('LoginRequest, RegisterRequest, and MerchantRegisterRequest include device fields', () {
      const login = LoginRequest(
        username: '0244000000',
        password: 'Password1!',
        deviceToken: 'fcm-tok-123',
        devicePlatform: 'ANDROID',
        deviceId: 'uuid-1234',
        appVersion: '1.1.1',
        locale: 'en_GH',
      );
      expect(login.toJson(), {
        'username': '0244000000',
        'password': 'Password1!',
        'deviceToken': 'fcm-tok-123',
        'devicePlatform': 'ANDROID',
        'deviceId': 'uuid-1234',
        'appVersion': '1.1.1',
        'locale': 'en_GH',
      });

      const register = RegisterRequest(
        firstName: 'Ama',
        lastName: 'Mensah',
        email: 'ama@example.com',
        phoneNumber: '0244000000',
        country: 'Ghana',
        password: 'Password1!',
        deviceToken: 'fcm-tok-123',
        devicePlatform: 'ANDROID',
        deviceId: 'unknown',
      );
      final regJson = register.toJson();
      expect(regJson['deviceToken'], 'fcm-tok-123');
      expect(regJson['devicePlatform'], 'ANDROID');
      expect(regJson.containsKey('deviceId'), isFalse);

      const merchant = MerchantRegisterRequest(
        name: 'Shop',
        email: 'shop@example.com',
        phoneNumber: '0244000000',
        password: 'Password1!',
        country: 'Ghana',
        deviceToken: 'fcm-tok-999',
        devicePlatform: 'IOS',
        deviceId: 'uuid-999',
      );
      expect(merchant.toJson()['deviceToken'], 'fcm-tok-999');
      expect(merchant.toJson()['devicePlatform'], 'IOS');
      expect(merchant.toJson()['deviceId'], 'uuid-999');
    });
  });

  group('Device token verification & refresh metadata', () {
    test('getActiveDeviceTokenCount counts active tokens', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter(
        (_) => _jsonBody('''
{
  "success": true,
  "data": {
    "tokens": [
      {"token": "t1", "isActive": true},
      {"token": "t2", "isActive": false}
    ],
    "total": 2
  }
}
'''),
      );
      final api = ApiClient(dio: dio, tokenStore: TokenStore(prefs));
      final repo = RemoteNotificationsRepository(api);
      expect(await repo.getActiveDeviceTokenCount(), 1);
    });

    test('refresh request includes deviceToken and device identity', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tokens = TokenStore(prefs);
      await tokens.saveSession(accessToken: 'old-access', refreshToken: 'ref-1');

      final dio = Dio();
      final refreshDio = Dio();
      var retried = false;
      dio.httpClientAdapter = _StubAdapter((options) {
        if (!retried) {
          retried = true;
          return _jsonBody('{"message":"Unauthorized"}', status: 401);
        }
        return _jsonBody('{"ok":true}');
      });
      final refreshAdapter = _StubAdapter(
        (_) => _jsonBody('{"access_token":"new-access","refresh_token":"ref-2"}'),
      );
      refreshDio.httpClientAdapter = refreshAdapter;

      const identity = DeviceIdentity(
        deviceId: 'install-uuid-1',
        platform: 'ANDROID',
        appVersion: '1.1.1',
        buildNumber: '32',
        locale: 'en_GH',
        model: 'Pixel',
        osVersion: 'Android 15',
        manufacturer: 'Google',
      );
      final api = ApiClient(
        dio: dio,
        refreshDio: refreshDio,
        tokenStore: tokens,
        deviceIdentity: identity,
        deviceTokenProvider: () => 'fcm-live-token',
      );

      await api.get('/api/v1/users/profile');
      expect(refreshAdapter.requests, hasLength(1));
      final body = refreshAdapter.requests.single.data as Map<String, dynamic>;
      expect(body['refreshToken'], 'ref-1');
      expect(body['deviceToken'], 'fcm-live-token');
      expect(body['devicePlatform'], 'ANDROID');
      expect(body['deviceId'], 'install-uuid-1');
      expect(body['appVersion'], '1.1.1');
      expect(body['locale'], 'en_GH');
    });
  });

  group('Pending recipient decisions recovery', () {
    test('getPendingDecisions parses active pending decisions and skips expired', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final futureExpiry = DateTime.now().add(const Duration(minutes: 3)).toUtc().toIso8601String();
      final pastExpiry = DateTime.now().subtract(const Duration(minutes: 1)).toUtc().toIso8601String();

      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter(
        (_) => _jsonBody('''
{
  "decisions": [
    {
      "decisionId": "DEC-ACTIVE",
      "topupOrderId": "TRX-1",
      "status": "PENDING",
      "serviceType": "AIRTIME",
      "recipientPhone": "233244000000",
      "amount": 15.0,
      "currency": "GHS",
      "senderName": "Kwame",
      "expiresAt": "$futureExpiry"
    },
    {
      "decisionId": "DEC-EXPIRED",
      "topupOrderId": "TRX-2",
      "status": "PENDING",
      "expiresAt": "$pastExpiry"
    }
  ],
  "count": 2
}
'''),
      );
      final repo = RemoteRecipientChoiceRepository(
        ApiClient(dio: dio, tokenStore: TokenStore(prefs)),
      );
      final decisions = await repo.getPendingDecisions();
      expect(decisions, hasLength(1));
      expect(decisions.single.decisionId, 'DEC-ACTIVE');
      expect(decisions.single.senderName, 'Kwame');
      expect(decisions.single.amount, 15.0);
    });

    test('PendingRecipientDecisionsNotifier claims each pending decision once', () async {
      final decision = RecipientDecision(
        decisionId: 'DEC-1',
        topupOrderId: 'TRX-1',
        status: DecisionStatus.pending,
        senderName: 'Kwame',
        amount: 20,
        currency: 'GHS',
        expiresAt: DateTime.now().add(const Duration(minutes: 3)),
      );
      final notifier = PendingRecipientDecisionsNotifier(
        _FakePendingRepo([decision]),
        hasSession: true,
        userKey: 'u1',
      );
      await notifier.refresh();
      expect(notifier.state, hasLength(1));
      expect(notifier.claimNextToSurface()?.decisionId, 'DEC-1');
      expect(notifier.claimNextToSurface(), isNull);
    });
  });
}
