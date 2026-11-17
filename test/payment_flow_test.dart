import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/core/deep_links.dart';
import 'package:lidapay_app/core/network/api_client.dart';
import 'package:lidapay_app/core/network/token_store.dart';
import 'package:lidapay_app/features/auth/data/auth_models.dart';
import 'package:lidapay_app/features/payments/data/payment_models.dart';
import 'package:lidapay_app/features/payments/data/payments_repository.dart';
import 'package:lidapay_app/features/payments/data/pending_payment.dart';
import 'package:lidapay_app/features/payments/data/pending_payment_store.dart';
import 'package:lidapay_app/features/payments/data/remote_payments_repository.dart';
import 'package:lidapay_app/features/payments/providers.dart';
import 'package:lidapay_app/features/services/data/mock_services_repository.dart';
import 'package:lidapay_app/features/services/data/service_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.respond);

  final Object? Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(respond(options)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<(ApiClient, _StubAdapter)> _client(
  Object? Function(RequestOptions options) respond,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final adapter = _StubAdapter(respond);
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
    ..httpClientAdapter = adapter;
  final refreshDio = Dio(BaseOptions(baseUrl: 'https://api.test'))
    ..httpClientAdapter = adapter;
  return (
    ApiClient(dio: dio, refreshDio: refreshDio, tokenStore: TokenStore(prefs)),
    adapter,
  );
}

// --- Fakes -----------------------------------------------------------------

class _FakePaymentsRepository implements PaymentsRepository {
  PaymentInitiation initiation = const PaymentInitiation(
    checkoutUrl: 'https://checkout.example/pay/1',
    token: 'saved-token',
    orderId: 'ADV-1',
  );
  final queue = <PaymentQueryResult>[];
  final initiateBodies = <Map<String, dynamic>>[];
  var queryCalls = 0;

  @override
  Future<PaymentInitiation> initiatePayment({
    required String userId,
    required String firstName,
    required String lastName,
    required String email,
    required String phoneNumber,
    required String username,
    required double amount,
    required String orderDesc,
    String? payTransRef,
    String transType = 'MOMO',
    String? shopOrderNumber,
    String? redirectUrl,
  }) async {
    initiateBodies.add({
      'userId': userId,
      'amount': amount,
      'orderDesc': orderDesc,
      'payTransRef': payTransRef,
      'transType': transType,
      if (shopOrderNumber != null) 'shopOrderNumber': shopOrderNumber,
    });
    return initiation;
  }

  @override
  Future<PaymentQueryResult> queryTransaction(String token) async {
    queryCalls++;
    if (queue.isNotEmpty) return queue.removeAt(0);
    return const PaymentQueryResult(status: 'PENDING');
  }

  final gtPayQueue = <GtPayResult>[];
  GtPayResult gtPayInitial = const GtPayResult(status: 'PENDING');
  final gtPayBodies = <Map<String, dynamic>>[];
  final gtPayStatusIds = <String>[];

  @override
  Future<GtPayResult> gtPayDebit({
    required String partnerTransId,
    required String userId,
    required String userName,
    required String momoNumber,
    required double amount,
    required String remarks,
    required String paidBy,
    String? shopOrderNumber,
  }) async {
    gtPayBodies.add({
      'PartnerTransId': partnerTransId,
      'momo': momoNumber,
      'amount': amount,
      if (shopOrderNumber != null) 'shopOrderNumber': shopOrderNumber,
    });
    return gtPayInitial;
  }

  @override
  Future<GtPayResult> gtPayStatus(String partnerTransId) async {
    gtPayStatusIds.add(partnerTransId);
    if (gtPayQueue.isNotEmpty) return gtPayQueue.removeAt(0);
    return const GtPayResult(status: 'PENDING');
  }
}

class _RecordingServices extends MockServicesRepository {
  final calls = <String>[];

  ServiceReceipt _receipt(String title) => ServiceReceipt(
    reference: 'RCPT-${calls.length}',
    title: title,
    message: 'done',
    amount: 10,
    createdAt: DateTime(2026),
  );

  @override
  Future<ServiceReceipt> buyLocalAirtime({
    required String recipientNumber,
    required double amount,
    required String networkId,
    required bool saveToLidaValue,
    required String clientReference,
    bool isSelfTopup = false,
  }) async {
    calls.add('localAirtime:$recipientNumber:$amount:$networkId');
    return _receipt('Airtime sent');
  }

  @override
  Future<ServiceReceipt> buyGlobalAirtime({
    required String recipientNumber,
    required double amount,
    required String countryCode,
    String? operatorId,
    String? recipientDialCode,
    String? recipientEmail,
    String? senderNumber,
    String senderCountryCode = 'GH',
    String currency = 'USD',
    required String clientReference,
    bool isSelfTopup = false,
  }) async {
    calls.add('globalAirtime:$recipientNumber:$countryCode:$operatorId');
    return _receipt('Airtime sent');
  }

  @override
  Future<ServiceReceipt> buyDataBundle({
    required String recipientNumber,
    required String networkId,
    required DataBundle bundle,
    required bool saveToLidaValue,
    required String clientReference,
    bool isSelfTopup = false,
  }) async {
    calls.add('ghanaData:$recipientNumber:${bundle.id}');
    return _receipt('Data sent');
  }

  @override
  Future<ServiceReceipt> buyGlobalDataBundle({
    required String recipientNumber,
    required double amount,
    required String countryCode,
    String? operatorId,
    String? operatorName,
    String? recipientDialCode,
    String? recipientEmail,
    String? senderNumber,
    String senderCountryCode = 'GH',
    String currency = 'USD',
    required String clientReference,
    bool isSelfTopup = false,
  }) async {
    calls.add('globalData:$recipientNumber:$countryCode');
    return _receipt('Data sent');
  }
}

const _user = UserProfile(
  id: 'user-1',
  firstName: 'Kofi',
  lastName: 'Mensah',
  email: 'kofi@example.com',
  phoneNumber: '0244000000',
  username: 'kofi',
  country: 'GH',
  emailVerified: true,
  phoneVerified: true,
  isVerified: true,
  kycStatus: 'verified',
);

Future<(PaymentSessionNotifier, _FakePaymentsRepository, _RecordingServices)>
_session({List<PaymentQueryResult>? queue}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final payments = _FakePaymentsRepository()..queue.addAll(queue ?? []);
  final services = _RecordingServices();
  final notifier = PaymentSessionNotifier(
    payments,
    PendingPaymentStore(prefs),
    services,
    (_) async => true,
    () => _user,
    queryAttempts: 3,
    queryDelay: Duration.zero,
    gtPayPollAttempts: 3,
    gtPayPollDelay: Duration.zero,
  );
  return (notifier, payments, services);
}

PendingPayment _ghanaAirtime() => PendingPayment.ghanaAirtime(
  reference: 'LDP-1',
  clientReference: 'LDP-test-pf-1',
  amount: 10,
  recipientNumber: '0244555666',
  networkId: '4',
  saveToLidaValue: false,
  isSelfTopup: false,
  orderDesc: 'test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('initiate-payment parsing', () {
    test('parses wrapped data with kebab-case order-id', () async {
      final (api, _) = await _client(
        (_) => {
          'status': 201,
          'message': 'Payment initiated successfully.',
          'data': {
            'order-id': 'ADV-M2NN2COD-11D269AA',
            'token': 'tok.123',
            'checkoutUrl': 'https://checkout.expresspay/pay/x',
          },
        },
      );
      final repo = RemotePaymentsRepository(api);
      final result = await repo.initiatePayment(
        userId: 'u1',
        firstName: 'K',
        lastName: 'M',
        email: 'k@m.com',
        phoneNumber: '0244000000',
        username: 'k',
        amount: 20,
        orderDesc: 'test',
      );
      expect(result.orderId, 'ADV-M2NN2COD-11D269AA');
      expect(result.token, 'tok.123');
      expect(result.isUsable, isTrue);
    });

    test('sends shopOrderNumber + payTransRef, never returnUrl', () async {
      final (api, adapter) = await _client(
        (_) => {
          'data': {'orderId': 'O1', 'token': 't', 'checkoutUrl': 'https://x'},
        },
      );
      final repo = RemotePaymentsRepository(api);
      await repo.initiatePayment(
        userId: 'u1',
        firstName: 'K',
        lastName: 'M',
        email: 'k@m.com',
        phoneNumber: '0244000000',
        username: 'k',
        amount: 158.58,
        orderDesc: 'shop',
        payTransRef: 'LDP-9',
        shopOrderNumber: 'LPS260912482913',
      );
      final body = adapter.requests.single.data as Map;
      expect(body['shopOrderNumber'], 'LPS260912482913');
      expect(body['payTransRef'], 'LDP-9');
      expect(body.containsKey('returnUrl'), isFalse);
      expect(body.containsKey('redirectUrl'), isFalse);
    });

    test('sends the shop redirectUrl when provided', () async {
      final (api, adapter) = await _client(
        (_) => {
          'data': {'orderId': 'O1', 'token': 't', 'checkoutUrl': 'https://x'},
        },
      );
      final repo = RemotePaymentsRepository(api);
      await repo.initiatePayment(
        userId: 'u1',
        firstName: 'K',
        lastName: 'M',
        email: 'k@m.com',
        phoneNumber: '0244000000',
        username: 'k',
        amount: 158.58,
        orderDesc: 'shop',
        shopOrderNumber: 'LPS260912482913',
        redirectUrl: 'lidapay://shop/checkout/callback',
      );
      final body = adapter.requests.single.data as Map;
      expect(body['shopOrderNumber'], 'LPS260912482913');
      expect(body['redirectUrl'], 'lidapay://shop/checkout/callback');
      expect(body.containsKey('returnUrl'), isFalse);
    });

    test('throws when the checkout payload is malformed', () async {
      final (api, _) = await _client(
        (_) => {
          'data': {'status': 'ok'},
        },
      );
      final repo = RemotePaymentsRepository(api);
      expect(
        () => repo.initiatePayment(
          userId: 'u1',
          firstName: 'K',
          lastName: 'M',
          email: 'k@m.com',
          phoneNumber: '0',
          username: 'k',
          amount: 1,
          orderDesc: 'x',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('query-transaction outcome', () {
    PaymentQueryResult parse(Map<String, dynamic> body) =>
        PaymentQueryResult.fromJson({'data': body});

    test('COMPLETED / APPROVED / PAID statuses succeed', () {
      for (final status in const [
        'COMPLETED',
        'APPROVED',
        'PAID',
        'SUCCESS',
        'SUCCESSFUL',
      ]) {
        expect(parse({'status': status}).outcome, PaymentOutcome.success);
      }
    });

    test('success resultText succeeds without a status', () {
      expect(
        parse({'resultText': 'Transaction Successful'}).outcome,
        PaymentOutcome.success,
      );
      // …but "Unsuccessful" must not match a naive contains('success').
      expect(
        parse({'resultText': 'Unsuccessful'}).outcome,
        isNot(PaymentOutcome.success),
      );
    });

    test('originalResponse result == 1 succeeds', () {
      expect(
        parse({
          'status': 'PENDING',
          'originalResponse': {'result': 1, 'result-text': 'Success'},
        }).outcome,
        PaymentOutcome.success,
      );
    });

    test('FAILED / CANCELLED statuses fail; anything else stays pending', () {
      expect(parse({'status': 'FAILED'}).outcome, PaymentOutcome.failed);
      expect(parse({'status': 'CANCELLED'}).outcome, PaymentOutcome.failed);
      expect(parse({'status': 'DECLINED'}).outcome, PaymentOutcome.failed);
      expect(
        parse({'resultText': 'Card error'}).outcome,
        PaymentOutcome.failed,
      );
      expect(parse({'status': 'PROCESSING'}).outcome, PaymentOutcome.pending);
      expect(parse({}).outcome, PaymentOutcome.pending);
    });
  });

  group('pending payment store', () {
    test('round-trips every kind with credit params', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = PendingPaymentStore(prefs);

      final payment = PendingPayment.globalAirtime(
        reference: 'LDP-7',
        clientReference: 'LDP-test-pf-2',
        payAmount: 95.5,
        payCurrency: 'GHS',
        deliverAmount: 10,
        deliverCurrency: 'NGN',
        recipientNumber: '2348130678848',
        countryCode: 'NG',
        operatorId: '341',
        recipientDialCode: '+234',
        senderNumber: '0244000000',
        isSelfTopup: false,
        orderDesc: 'Lidapay airtime top-up',
      ).copyWith(token: 'tok', advansisOrderId: 'ADV-9');

      await store.save(payment);
      final loaded = store.load()!;
      expect(loaded.kind, PendingPaymentKind.globalAirtime);
      expect(loaded.reference, 'LDP-7');
      expect(loaded.token, 'tok');
      expect(loaded.params['operatorId'], '341');
      expect(loaded.params['senderCountryCode'], 'GH');
      await store.clear();
      expect(store.load(), isNull);
    });
  });

  group('payment session', () {
    test(
      'begin persists + launches; return verifies and credits Ghana airtime',
      () async {
        final (session, payments, services) = await _session(
          queue: [
            const PaymentQueryResult(
              status: 'COMPLETED',
              transactionId: 'TX-1',
            ),
          ],
        );

        expect(await session.beginPayment(_ghanaAirtime()), isTrue);
        expect(session.state.phase, PaymentPhase.awaitingCallback);
        expect(session.pendingPayment?.token, 'saved-token');

        await session.handleReturn(status: 'success', orderId: 'ADV-1');

        expect(session.state.phase, PaymentPhase.completed);
        expect(session.state.receipt, isNotNull);
        expect(services.calls, ['localAirtime:0244555666:10.0:4']);
        expect(payments.queryCalls, 1);
      },
    );

    test('initiation sends payTransRef and MOMO transType', () async {
      final (session, payments, _) = await _session();
      await session.beginPayment(_ghanaAirtime());
      final body = payments.initiateBodies.single;
      expect(body['payTransRef'], 'LDP-1');
      expect(body['transType'], 'MOMO');
      expect(body['amount'], 10);
    });

    test('a mismatched order-id is ignored, not queried', () async {
      final (session, payments, services) = await _session();
      await session.beginPayment(_ghanaAirtime());
      await session.handleReturn(status: 'success', orderId: 'WRONG-ORDER');
      expect(session.state.phase, PaymentPhase.awaitingCallback);
      expect(payments.queryCalls, 0);
      expect(services.calls, isEmpty);
    });

    test(
      'pending queries exhaust back to awaiting, recheck finishes it',
      () async {
        final (session, payments, services) = await _session(
          queue: [
            const PaymentQueryResult(status: 'PENDING'),
            const PaymentQueryResult(status: 'PENDING'),
            const PaymentQueryResult(status: 'PENDING'),
            const PaymentQueryResult(status: 'SUCCESS'),
          ],
        );
        await session.beginPayment(_ghanaAirtime());
        await session.recheck();
        expect(session.state.phase, PaymentPhase.awaitingCallback);
        expect(payments.queryCalls, 3);
        await session.recheck();
        expect(session.state.phase, PaymentPhase.completed);
        expect(services.calls, hasLength(1));
      },
    );

    test('terminal failure clears the pending slot', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = PendingPaymentStore(prefs);
      final payments = _FakePaymentsRepository()
        ..queue.add(const PaymentQueryResult(status: 'FAILED'));
      final session = PaymentSessionNotifier(
        payments,
        store,
        _RecordingServices(),
        (_) async => true,
        () => _user,
        queryAttempts: 3,
        queryDelay: Duration.zero,
      );
      await session.beginPayment(_ghanaAirtime());
      await session.handleReturn(status: 'error', orderId: 'ADV-1');
      expect(session.state.phase, PaymentPhase.failed);
      expect(store.load(), isNull);
    });

    test(
      'concurrent return + recheck single-flights — no double credit',
      () async {
        final (session, _, services) = await _session(
          queue: [const PaymentQueryResult(status: 'COMPLETED')],
        );
        await session.beginPayment(_ghanaAirtime());
        await Future.wait([
          session.handleReturn(status: 'success', orderId: 'ADV-1'),
          session.recheck(),
        ]);
        expect(session.state.phase, PaymentPhase.completed);
        expect(services.calls, hasLength(1));
      },
    );

    test('global airtime credits through the Reloadly route', () async {
      final (session, _, services) = await _session(
        queue: [const PaymentQueryResult(status: 'COMPLETED')],
      );
      final draft = PendingPayment.globalAirtime(
        reference: 'LDP-8',
        clientReference: 'LDP-test-pf-3',
        payAmount: 95.5,
        payCurrency: 'GHS',
        deliverAmount: 10,
        deliverCurrency: 'NGN',
        recipientNumber: '2348130678848',
        countryCode: 'NG',
        operatorId: '341',
        recipientDialCode: '+234',
        isSelfTopup: false,
        orderDesc: 'test',
      );
      await session.beginPayment(draft);
      await session.handleReturn(status: 'success', orderId: 'ADV-1');
      expect(session.state.phase, PaymentPhase.completed);
      expect(services.calls, ['globalAirtime:2348130678848:NG:341']);
    });

    test('cancelPending abandons an unverified initiation', () async {
      final (session, _, services) = await _session();
      await session.beginPayment(_ghanaAirtime());
      await session.cancelPending();
      expect(session.state.phase, PaymentPhase.idle);
      expect(session.pendingPayment, isNull);
      expect(services.calls, isEmpty);
    });
  });

  group('GTPay mobile money', () {
    test('parses wrapped pay response Status, not envelope status', () {
      final result = GtPayResult.fromJson({
        'status': 200,
        'message': 'ok',
        'data': {
          'PartnerTransId': '1789123510110926',
          'Status': 'PENDING',
          'Data': {'Network': 'MTN', 'Charge': 0, 'TotalAmount': 10.5},
        },
      });
      expect(result.status, 'PENDING');
      expect(result.outcome, PaymentOutcome.pending);
      expect(result.partnerTransId, '1789123510110926');
      expect(result.network, 'MTN');
      expect(result.totalAmount, 10.5);
    });

    test('remote debit sends debitwallet with exact decimal amount', () async {
      final (api, adapter) = await _client(
        (_) => {
          'status': 200,
          'data': {'PartnerTransId': '123', 'Status': 'PENDING'},
        },
      );
      await RemotePaymentsRepository(api).gtPayDebit(
        partnerTransId: '123',
        userId: 'user-1',
        userName: 'kofi',
        momoNumber: '0244000000',
        amount: 158.5,
        remarks: 'Lidapay shop order LPS1',
        paidBy: 'Kofi Mensah',
        shopOrderNumber: 'LPS1',
      );
      final req = adapter.requests.single;
      expect(req.path, '/api/v1/gtpay/pay');
      final body = req.data as Map;
      expect(body['shopOrderNumber'], 'LPS1');
      final details = body['ServiceDetails'] as Map;
      expect(details['ServiceName'], 'debitwallet');
      expect(details['ServiceNumber'], '0244000000');
      expect(details['Amount'], '158.50');
    });

    test('normalises and validates Ghana MoMo numbers', () {
      expect(normalizeMomoNumber('+233 24 400 0000'), '0244000000');
      expect(normalizeMomoNumber('244000000'), '0244000000');
      expect(isValidMomoNumber('0244000000'), isTrue);
      expect(isValidMomoNumber('0144000000'), isFalse);
      expect(isValidMomoNumber('02440'), isFalse);
    });

    test('pending debit polls status with the same PartnerTransId then '
        'delivers', () async {
      final (session, payments, services) = await _session();
      payments.gtPayQueue.addAll(const [
        GtPayResult(status: 'PENDING'),
        GtPayResult(status: 'COMPLETED'),
      ]);
      final started = await session.beginPayment(
        _ghanaAirtime(),
        method: PaymentMethod.mobileMoney,
        momoNumber: '233244000000',
      );
      expect(started, isTrue);
      await session.recheck();
      await pumpEventQueue();

      final sentId = payments.gtPayBodies.single['PartnerTransId'] as String;
      expect(payments.gtPayBodies.single['momo'], '0244000000');
      expect(sentId.length, lessThanOrEqualTo(20));
      expect(int.tryParse(sentId), isNotNull);
      expect(payments.gtPayStatusIds, everyElement(sentId));
      expect(payments.initiateBodies, isEmpty);
      expect(services.calls, hasLength(1));
      expect(session.state.phase, PaymentPhase.completed);
    });

    test('declined debit lands on not-confirmed, never delivers, and '
        'retry issues a fresh PartnerTransId', () async {
      final (session, payments, services) = await _session();
      payments.gtPayInitial = const GtPayResult(
        status: 'FAILED',
        message: 'Insufficient funds',
      );
      final started = await session.beginPayment(
        _ghanaAirtime(),
        method: PaymentMethod.mobileMoney,
        momoNumber: '0244000000',
      );
      expect(started, isTrue);
      expect(session.state.phase, PaymentPhase.awaitingCallback);
      expect(session.state.providerStatus, 'FAILED');
      expect(services.calls, isEmpty);
      // The purchase stays pending so the user can check again — never
      // silently declared failed on one report.
      expect(session.pendingPayment, isNotNull);
      final firstTransId = session.pendingPayment!.partnerTransId;

      final retried = await session.retryMobileMoney();
      expect(retried, isTrue);
      final secondTransId = session.pendingPayment!.partnerTransId;
      expect(secondTransId, isNot(firstTransId));
      expect(payments.gtPayBodies, hasLength(2));
      expect(services.calls, isEmpty);
    });

    test('invalid MoMo number never reaches GTPay', () async {
      final (session, payments, _) = await _session();
      final started = await session.beginPayment(
        _ghanaAirtime(),
        method: PaymentMethod.mobileMoney,
        momoNumber: '12345',
      );
      expect(started, isFalse);
      expect(payments.gtPayBodies, isEmpty);
    });

    test('still-pending after poll window stays recoverable', () async {
      final (session, payments, services) = await _session();
      await session.beginPayment(
        _ghanaAirtime(),
        method: PaymentMethod.mobileMoney,
        momoNumber: '0244000000',
      );
      await pumpEventQueue();
      expect(session.state.phase, PaymentPhase.awaitingCallback);
      expect(session.pendingPayment?.partnerTransId, isNotNull);
      expect(services.calls, isEmpty);
    });

    test('expired approval window stops polling and lands on timed-out',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final payments = _FakePaymentsRepository();
      final services = _RecordingServices();
      final session = PaymentSessionNotifier(
        payments,
        PendingPaymentStore(prefs),
        services,
        (_) async => true,
        () => _user,
        gtPayExpireAfter: Duration.zero,
      );
      final started = await session.beginPayment(
        _ghanaAirtime(),
        method: PaymentMethod.mobileMoney,
        momoNumber: '0244000000',
      );
      expect(started, isTrue);
      await pumpEventQueue();
      expect(session.state.phase, PaymentPhase.awaitingCallback);
      expect(session.state.providerStatus, 'TIMED_OUT');
      // One status query to catch a late approval — never a poll window.
      expect(payments.gtPayStatusIds, hasLength(1));
      expect(services.calls, isEmpty);
    });

    test('PaymentDeepLinkHandler parses ExpressPay redirect-url callbacks', () {
      final uri = Uri.parse(
        'lidapay://redirect-url?orderId=ADV-9&token=tok-1&status=success',
      );
      expect(PaymentDeepLinkHandler.isPaymentReturn(uri), isTrue);
      expect(PaymentDeepLinkHandler.isPasswordLink(uri), isFalse);
      final target = PaymentDeepLinkHandler.callbackRouteFor(uri);
      expect(
        target,
        '/payment/callback?status=success&orderId=ADV-9&hasToken=1',
      );
    });

    test('handleReturn reconciles shop order when orderId is shop orderNumber',
        () async {
      final (session, payments, _) = await _session();
      payments.queue.add(const PaymentQueryResult(status: 'PAID'));
      await session.beginPayment(
        PendingPayment.shopOrder(
          reference: 'LDP-SHOP-1',
          clientReference: 'LDP-test-pf-4',
          orderId: 'mongo-ord-1',
          orderNumber: 'LPS261116000099',
          total: 120,
          currency: 'GHS',
        ),
      );
      await session.handleReturn(
        status: 'success',
        orderId: 'LPS261116000099',
        token: 'present',
      );

      expect(payments.queryCalls, 1);
      expect(session.state.phase, PaymentPhase.completed);
      expect(session.state.shopOrderNumber, 'LPS261116000099');
    });
  });
}
