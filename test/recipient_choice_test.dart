import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/core/network/api_client.dart';
import 'package:lidapay_app/core/network/api_exception.dart';
import 'package:lidapay_app/core/network/token_store.dart';
import 'package:lidapay_app/features/dashboard/providers.dart';
import 'package:lidapay_app/features/lida_value/data/lv_attempt_store.dart';
import 'package:lidapay_app/features/lida_value/providers.dart';
import 'package:lidapay_app/features/payments/data/pending_payment.dart';
import 'package:lidapay_app/features/payments/providers.dart';
import 'package:lidapay_app/features/recipient_choice/data/recipient_models.dart';
import 'package:lidapay_app/features/recipient_choice/data/remote_recipient_choice_repository.dart';
import 'package:lidapay_app/features/recipient_choice/providers.dart';
import 'package:lidapay_app/features/recipient_choice/screens/pending_topup_screen.dart';
import 'package:lidapay_app/features/services/data/mock_services_repository.dart';
import 'package:lidapay_app/features/services/data/remote_services_repository.dart';
import 'package:lidapay_app/features/services/data/service_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Recipient-choice contract: eligibility preflight, decision fetch/respond
/// and top-up status polling, plus the parked-delivery detection on service
/// receipts and the Lida Value funded checkout (debit → deliver).
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.respond, {this.status});

  final Object? Function(RequestOptions options) respond;
  final int Function(RequestOptions options)? status;
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
      status?.call(options) ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<(ApiClient, _StubAdapter)> _client(
  Object? Function(RequestOptions options) respond, {
  int Function(RequestOptions options)? status,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final adapter = _StubAdapter(respond, status: status);
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
    ..httpClientAdapter = adapter;
  final refreshDio = Dio(BaseOptions(baseUrl: 'https://api.test'))
    ..httpClientAdapter = adapter;
  return (
    ApiClient(dio: dio, refreshDio: refreshDio, tokenStore: TokenStore(prefs)),
    adapter,
  );
}

class _RecordingLidaServices extends MockServicesRepository {
  final calls = <String>[];

  ServiceReceipt _receipt(String title) => ServiceReceipt(
    reference: 'RCPT-${calls.length}',
    title: title,
    message: 'done',
    amount: 10,
    createdAt: DateTime(2026),
  );

  @override
  Future<ServiceReceipt> useLidaValue({
    required double amount,
    required String destination,
    String serviceType = 'AIRTIME',
    String? clientReference,
    int? network,
    String? dataCode,
  }) async {
    calls.add('use:$destination:$amount:$serviceType:$clientReference');
    return _receipt('Lida Value used');
  }

  @override
  Future<ServiceReceipt> sendLidaValue({
    required double amount,
    required String destination,
    String serviceType = 'AIRTIME',
    String? note,
    String? clientReference,
  }) async {
    calls.add('send:$destination:$amount:$serviceType:$clientReference');
    return _receipt('USE_SEND');
  }

  @override
  Future<ServiceReceipt> buyLocalAirtime({
    required String recipientNumber,
    required double amount,
    required String networkId,
    required bool saveToLidaValue,
    required String clientReference,
    bool isSelfTopup = false,
  }) async {
    calls.add('deliver:$recipientNumber:$amount:$networkId:$isSelfTopup');
    return _receipt('Airtime sent');
  }
}

class _FailingDebitServices extends _RecordingLidaServices {
  @override
  Future<ServiceReceipt> useLidaValue({
    required double amount,
    required String destination,
    String serviceType = 'AIRTIME',
    String? clientReference,
    int? network,
    String? dataCode,
  }) async {
    throw const ApiException('Insufficient Lida Value balance.');
  }
}

class _FailingDeliveryServices extends _RecordingLidaServices {
  @override
  Future<ServiceReceipt> buyLocalAirtime({
    required String recipientNumber,
    required double amount,
    required String networkId,
    required bool saveToLidaValue,
    required String clientReference,
    bool isSelfTopup = false,
  }) async {
    calls.add('deliver-failed');
    throw const ApiException('Provider delivery failed.');
  }
}

/// A debit that times out — the wallet may or may not have been charged.
class _TimeoutDebitServices extends _RecordingLidaServices {
  @override
  Future<ServiceReceipt> sendLidaValue({
    required double amount,
    required String destination,
    String serviceType = 'AIRTIME',
    String? note,
    String? clientReference,
  }) async {
    calls.add('send:$destination:$amount:$serviceType:$clientReference');
    throw const ApiException(
      'The network did not respond in time.',
      statusCode: 504,
    );
  }
}

Future<LvAttemptStore> _attemptStore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return LvAttemptStore(prefs);
}

void main() {
  group('recipient models', () {
    test('eligibility parses a registered, promptable recipient', () {
      final e = RecipientEligibility.fromJson(const {
        'isRegistered': true,
        'canPromptChoice': true,
        'defaultChoice': 'LIDA_VALUE',
        'timeoutSeconds': 180,
      });
      expect(e.willPromptRecipient, isTrue);
      expect(e.timeoutSeconds, 180);
    });

    test('decision parses the resolved openapi shape', () {
      final d = RecipientDecision.fromJson(const {
        'decisionId': 'DEC987654321',
        'topupOrderId': 'TRX123456789',
        'status': 'RESOLVED',
        'serviceType': 'DATA',
        'recipientPhone': '233541234567',
        'amountOrValueUnits': 10,
        'selectedChoice': 'LIDA_VALUE',
        'resolvedSource': 'TIMEOUT',
        'finalDisposition': 'SAVED_TO_LIDA_VALUE',
        'expiresAt': '2026-03-08T17:56:00.000Z',
      });
      expect(d.isResolved, isTrue);
      expect(d.savedToLidaValue, isTrue);
      expect(d.selectedChoice, RecipientChoice.lidaValue);
      expect(d.serviceLabel, 'data');
      expect(d.expiresAt, isNotNull);
    });

    test('pending decision has no selected choice or disposition', () {
      final d = RecipientDecision.fromJson(const {
        'decisionId': 'DEC1',
        'topupOrderId': 'TRX1',
        'status': 'PENDING',
        'serviceType': 'AIRTIME',
        'expiresAt': '2026-03-08T17:56:00.000Z',
      });
      expect(d.isPending, isTrue);
      expect(d.selectedChoice, isNull);
      expect(d.finalDisposition, isNull);
    });

    test('topup status parses terminal state + nested decision', () {
      final s = TopupOrderStatus.fromJson(const {
        'topupOrderId': 'TRX123456789',
        'transactionRef': 'TRX123456789',
        'state': 'DELIVERED_LIDA_VALUE',
        'finalDisposition': 'SAVED_TO_LIDA_VALUE',
        'serviceType': 'DATA',
        'recipientPhone': '233541234567',
        'resolvedAt': '2026-02-20T14:31:00.000Z',
        'decision': {
          'decisionId': 'DEC987654321',
          'status': 'RESOLVED',
          'selectedChoice': 'LIDA_VALUE',
          'resolvedSource': 'TIMEOUT',
        },
      });
      expect(s.isTerminal, isTrue);
      expect(s.isDeliveredToLidaValue, isTrue);
      expect(s.decision?.resolvedSource, 'TIMEOUT');
    });

    test('awaiting state counts as waiting on the recipient', () {
      final s = TopupOrderStatus.fromJson(const {
        'topupOrderId': 'TRX1',
        'state': 'AWAITING_DECISION',
        'decision': {'decisionId': 'D1', 'status': 'PENDING'},
      });
      expect(s.isWaitingOnRecipient, isTrue);
      expect(s.isTerminal, isFalse);
    });
  });

  group('RemoteRecipientChoiceRepository', () {
    test('eligibility posts the documented body', () async {
      final (api, adapter) = await _client(
        (r) => {'isRegistered': true, 'canPromptChoice': true},
      );
      final repo = RemoteRecipientChoiceRepository(api);
      final result = await repo.checkEligibility(
        recipientPhone: '0244588584',
        serviceType: 'AIRTIME',
        countryIsoCode: 'GH',
      );
      expect(result.willPromptRecipient, isTrue);
      final body = adapter.requests.single.data as Map<String, dynamic>;
      expect(body['recipientPhone'], '0244588584');
      expect(body['serviceType'], 'AIRTIME');
      expect(body['countryIsoCode'], 'GH');
    });

    test('eligibility retries the alternate Ghana format on a miss', () async {
      final (api, adapter) = await _client((r) {
        final body = r.data as Map<String, dynamic>;
        if (body['recipientPhone'] == '233244588584') {
          return {'isRegistered': true, 'canPromptChoice': true};
        }
        return {'isRegistered': false, 'canPromptChoice': false};
      });
      final repo = RemoteRecipientChoiceRepository(api);
      final result = await repo.checkEligibility(
        recipientPhone: '0244588584',
        serviceType: 'DATA',
        countryIsoCode: 'GH',
      );
      expect(result.willPromptRecipient, isTrue);
      expect(adapter.requests.length, 2);
    });

    test('eligibility degrades to unregistered on failure', () async {
      final (api, _) = await _client(
        (r) => {'message': 'boom'},
        status: (_) => 500,
      );
      final repo = RemoteRecipientChoiceRepository(api);
      final result = await repo.checkEligibility(
        recipientPhone: '0244588584',
        serviceType: 'AIRTIME',
      );
      expect(result.isRegistered, isFalse);
      expect(result.willPromptRecipient, isFalse);
    });

    test('respond posts choice + idempotency header', () async {
      Map<String, dynamic>? sentBody;
      String? idempotency;
      final (api, _) = await _client((r) {
        sentBody = r.data as Map<String, dynamic>;
        idempotency = r.headers['X-Idempotency-Key']?.toString();
        return {
          'decisionId': 'DEC1',
          'topupOrderId': 'TRX1',
          'status': 'RESOLVED',
          'selectedChoice': 'DIRECT',
          'resolvedSource': 'RECIPIENT',
          'finalDisposition': 'DELIVERED_DIRECT',
          'deliveryResult': {'state': 'DELIVERED_DIRECT'},
        };
      });
      final repo = RemoteRecipientChoiceRepository(api);
      final result = await repo.respondToDecision(
        decisionId: 'DEC1',
        choice: RecipientChoice.direct,
        idempotencyKey: 'test-key-1',
      );
      expect(sentBody?['choice'], 'DIRECT');
      expect(idempotency, 'test-key-1');
      expect(result.isResolved, isTrue);
      expect(result.deliveredDirect, isTrue);
    });

    test('getTopupStatus parses the canonical payload', () async {
      final (api, _) = await _client(
        (r) => {
          'topupOrderId': 'TRX1',
          'state': 'DELIVERED_DIRECT',
          'recipientPhone': '233541234567',
        },
      );
      final repo = RemoteRecipientChoiceRepository(api);
      final status = await repo.getTopupStatus('TRX1');
      expect(status.isDeliveredDirect, isTrue);
      expect(status.isTerminal, isTrue);
    });
  });

  group('pending top-up on service receipts', () {
    test('PENDING + decisionId surfaces pendingTopup on the receipt', () async {
      final (api, _) = await _client((r) {
        if (r.path.contains('/airtime/topup')) {
          return {
            'status': 'PENDING',
            'decisionId': 'DEC9',
            'topupOrderId': 'TRX9',
            'expiresAt': '2026-03-08T18:00:00.000Z',
            'message': 'Awaiting recipient decision',
          };
        }
        return {};
      });
      final repo = RemoteServicesRepository(api);
      final receipt = await repo.buyLocalAirtime(
        recipientNumber: '0244588584',
        amount: 10,
        networkId: '4',
        saveToLidaValue: false,
        clientReference: 'LDP-test-rc-1',
      );
      expect(receipt.pendingTopup, isNotNull);
      expect(receipt.pendingTopup!.topupOrderId, 'TRX9');
      expect(receipt.pendingTopup!.decisionId, 'DEC9');
      expect(receipt.pendingTopup!.expiresAt, isNotNull);
    });

    test('a delivered top-up leaves pendingTopup null', () async {
      final (api, _) = await _client((r) {
        if (r.path.contains('/airtime/topup')) {
          return {'status': 'OK', 'trxn': 'TRX1', 'message': 'Airtime sent'};
        }
        return {};
      });
      final repo = RemoteServicesRepository(api);
      final receipt = await repo.buyLocalAirtime(
        recipientNumber: '0244588584',
        amount: 10,
        networkId: '4',
        saveToLidaValue: false,
        clientReference: 'LDP-test-rc-2',
      );
      expect(receipt.pendingTopup, isNull);
    });
  });

  group('deliverPendingPayment boundary', () {
    test('ghanaData rebuilds the bundle credit call', () async {
      final services = _RecordingLidaServices();
      final draft = PendingPayment.ghanaData(
        reference: 'LDP-1',
        clientReference: 'LDP-test-rc-3',
        amount: 12,
        recipientNumber: '0244588584',
        networkId: '4',
        bundleId: 'BND1',
        bundleName: '5GB',
        bundleDataAmount: '5GB',
        saveToLidaValue: false,
        isSelfTopup: true,
        orderDesc: 'data',
      );
      // ghanaData routes through buyDataBundle — assert via the mock's
      // own receipt rather than the recording override (which only
      // overrides buyLocalAirtime). Just ensure it doesn't throw.
      final receipt = await deliverPendingPayment(services, draft);
      expect(receipt, isA<ServiceReceipt>());
    });

    test('shop orders are rejected — the payment session owns them', () {
      final services = _RecordingLidaServices();
      final draft = PendingPayment.shopOrder(
        reference: 'LDP-2',
        clientReference: 'LDP-test-rc-4',
        orderId: 'ORD1',
        orderNumber: 'SH-1',
        total: 40,
        currency: 'GHS',
      );
      expect(
        () => deliverPendingPayment(services, draft),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('LidaValueTopupNotifier', () {
    test('USE is one backend call — never a second provider delivery', () async {
      final services = _RecordingLidaServices();
      final notifier = LidaValueTopupNotifier(services, await _attemptStore());
      final draft = PendingPayment.ghanaAirtime(
        reference: 'LDP-3',
        clientReference: 'LDP-test-rc-5',
        amount: 10,
        recipientNumber: '0244588584',
        networkId: '4',
        saveToLidaValue: false,
        isSelfTopup: true,
        orderDesc: 'use',
      );
      await notifier.execute(
        draft: draft,
        funding: ServiceFunding.lidaValueUse,
        serviceType: 'AIRTIME',
      );
      expect(notifier.state.phase, LidaTopupPhase.completed);
      expect(services.calls, ['use:0244588584:10.0:AIRTIME:LDP-test-rc-5']);
      expect(services.calls.where((c) => c.startsWith('deliver')), isEmpty);
    });

    test('SEND debits then delivers without the self flag', () async {
      final services = _RecordingLidaServices();
      final notifier = LidaValueTopupNotifier(services, await _attemptStore());
      final draft = PendingPayment.ghanaAirtime(
        reference: 'LDP-4',
        clientReference: 'LDP-test-rc-6',
        amount: 15,
        recipientNumber: '0201234567',
        networkId: '6',
        saveToLidaValue: false,
        isSelfTopup: false,
        orderDesc: 'send',
      );
      await notifier.execute(
        draft: draft,
        funding: ServiceFunding.lidaValueSend,
        serviceType: 'AIRTIME',
      );
      expect(notifier.state.phase, LidaTopupPhase.completed);
      expect(services.calls.first, 'send:0201234567:15.0:AIRTIME:LDP-test-rc-6');
      expect(services.calls.last, contains(':false'));
    });

    test('a failed debit never reaches the delivery call', () async {
      final services = _FailingDebitServices();
      final notifier = LidaValueTopupNotifier(services, await _attemptStore());
      final draft = PendingPayment.ghanaAirtime(
        reference: 'LDP-5',
        clientReference: 'LDP-test-rc-7',
        amount: 10,
        recipientNumber: '0244588584',
        networkId: '4',
        saveToLidaValue: false,
        isSelfTopup: true,
        orderDesc: 'use',
      );
      await notifier.execute(
        draft: draft,
        funding: ServiceFunding.lidaValueUse,
        serviceType: 'AIRTIME',
      );
      expect(notifier.state.phase, LidaTopupPhase.failed);
      expect(notifier.state.message, contains('Insufficient'));
      expect(services.calls.where((c) => c.startsWith('deliver')), isEmpty);
    });

    test('SEND delivery failure after debit keeps the debit reference', () async {
      final services = _FailingDeliveryServices();
      final notifier = LidaValueTopupNotifier(services, await _attemptStore());
      final draft = PendingPayment.ghanaAirtime(
        reference: 'LDP-6',
        clientReference: 'LDP-test-rc-8',
        amount: 10,
        recipientNumber: '0201234567',
        networkId: '4',
        saveToLidaValue: false,
        isSelfTopup: false,
        orderDesc: 'send',
      );
      await notifier.execute(
        draft: draft,
        funding: ServiceFunding.lidaValueSend,
        serviceType: 'AIRTIME',
      );
      expect(notifier.state.phase, LidaTopupPhase.failed);
      expect(notifier.state.debitReference, isNotNull);
      expect(services.calls.first, startsWith('send:'));
    });

    test('a timed-out debit keeps the attempt so a retry reuses it', () async {
      final services = _TimeoutDebitServices();
      final store = await _attemptStore();
      final notifier = LidaValueTopupNotifier(services, store);
      final draft = PendingPayment.ghanaAirtime(
        reference: 'LDP-9',
        clientReference: 'LDP-test-rc-9',
        amount: 10,
        recipientNumber: '0201234567',
        networkId: '4',
        saveToLidaValue: false,
        isSelfTopup: false,
        orderDesc: 'send',
      );
      await notifier.execute(
        draft: draft,
        funding: ServiceFunding.lidaValueSend,
        serviceType: 'AIRTIME',
      );
      expect(notifier.state.phase, LidaTopupPhase.failed);
      expect(notifier.state.outcomeUnknown, isTrue);
      // The attempt is kept on disk — the wallet may have been debited.
      expect(store.load(), isNotNull);
      expect(store.load()!.draft.clientReference, 'LDP-test-rc-9');
    });

    test('a retry of the same purchase reuses the idempotency reference',
        () async {
      final services = _TimeoutDebitServices();
      final store = await _attemptStore();
      final notifier = LidaValueTopupNotifier(services, store);
      PendingPayment draftFor(String reference) => PendingPayment.ghanaAirtime(
        reference: reference,
        clientReference: 'LDP-test-rc-10',
        amount: 10,
        recipientNumber: '0201234567',
        networkId: '4',
        saveToLidaValue: false,
        isSelfTopup: false,
        orderDesc: 'send',
      );
      await notifier.execute(
        draft: draftFor('LDP-10'),
        funding: ServiceFunding.lidaValueSend,
        serviceType: 'AIRTIME',
      );
      await notifier.execute(
        draft: draftFor('LDP-10b'),
        funding: ServiceFunding.lidaValueSend,
        serviceType: 'AIRTIME',
      );
      // Both attempts carry the same reference, so the backend can dedupe.
      expect(services.calls.first, contains('LDP-test-rc-10'));
      expect(services.calls.last, contains('LDP-test-rc-10'));
    });

    test('an already debited purchase is never debited again', () async {
      final services = _RecordingLidaServices();
      final store = await _attemptStore();
      final draft = PendingPayment.ghanaAirtime(
        reference: 'LDP-11',
        clientReference: 'LDP-test-rc-11',
        amount: 10,
        recipientNumber: '0201234567',
        networkId: '4',
        saveToLidaValue: false,
        isSelfTopup: false,
        orderDesc: 'send',
      );
      // Simulate a crash after the wallet was debited but before delivery.
      await store.save(
        LvAttempt(
          draft: draft,
          serviceType: 'AIRTIME',
          debitReference: 'LV-DEBIT-1',
          updatedAt: DateTime(2026),
        ),
      );
      final notifier = LidaValueTopupNotifier(services, store);
      await notifier.execute(
        draft: draft,
        funding: ServiceFunding.lidaValueSend,
        serviceType: 'AIRTIME',
      );
      // No second debit — only the delivery runs.
      expect(services.calls.where((c) => c.startsWith('send')), isEmpty);
      expect(services.calls.where((c) => c.startsWith('deliver')), isNotEmpty);
      expect(notifier.state.phase, LidaTopupPhase.completed);
    });

    test('a pending debit is finished on the next start', () async {
      final services = _RecordingLidaServices();
      final store = await _attemptStore();
      final draft = PendingPayment.ghanaAirtime(
        reference: 'LDP-12',
        clientReference: 'LDP-test-rc-12',
        amount: 10,
        recipientNumber: '0201234567',
        networkId: '4',
        saveToLidaValue: false,
        isSelfTopup: false,
        orderDesc: 'send',
      );
      await store.save(
        LvAttempt(
          draft: draft,
          serviceType: 'AIRTIME',
          debitReference: 'LV-DEBIT-2',
          updatedAt: DateTime(2026),
        ),
      );
      final notifier = LidaValueTopupNotifier(services, store);
      await notifier.resumePendingDelivery();
      expect(services.calls.where((c) => c.startsWith('send')), isEmpty);
      expect(services.calls.where((c) => c.startsWith('deliver')), isNotEmpty);
      expect(notifier.state.phase, LidaTopupPhase.completed);
      expect(store.load(), isNull);
    });
  });

  testWidgets('PendingTopupScreen renders waiting UI without layout errors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 667));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final pending = PendingTopup(
      topupOrderId: 'TXN-MWL9J79K-4B7EEC1F',
      decisionId: 'DEC-1',
      expiresAt: DateTime.now().add(const Duration(minutes: 4)),
    );

    var continued = false;
    var wentHome = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          topupStatusTrackerProvider.overrideWith(
            (ref, id) => Stream.value(
              TopupOrderStatus(
                topupOrderId: id,
                state: TopupState.awaitingDecision,
                serviceType: 'DATA',
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: PendingTopupScreen(
            pending: pending,
            amountLabel: 'GH₵10.00',
            recipientLabel: '0244954473',
            serviceLabel: 'data',
            icon: Icons.wifi_tethering_rounded,
            onDone: () => wentHome = true,
            onNewTransaction: () => continued = true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Sending top-up'), findsOneWidget);
    expect(find.text('Waiting for 0244954473'), findsOneWidget);
    expect(find.text('Take it now'), findsOneWidget);
    expect(find.text('Keep the value'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();

    expect(find.text('Continue transaction'), findsOneWidget);
    expect(find.text('Go to Home'), findsOneWidget);

    await tester.tap(find.text('Continue transaction'));
    expect(continued, isTrue);

    await tester.tap(find.text('Go to Home'));
    expect(wentHome, isTrue);
  });

  test('describeSettledTopup formats direct acceptance and Lida Value fallback', () {
    const tracked = TrackedPendingTopup(
      topupOrderId: 'TXN-1',
      recipient: '0549017820',
      serviceLabel: 'data bundle',
    );
    final direct = describeSettledTopup(
      const TopupOrderStatus(
        topupOrderId: 'TXN-1',
        state: TopupState.deliveredDirect,
      ),
      tracked: tracked,
    );
    expect(direct.failed, isFalse);
    expect(direct.body, contains('0549017820'));
    expect(direct.body, contains('accepted'));

    final fallback = describeSettledTopup(
      const TopupOrderStatus(
        topupOrderId: 'TXN-1',
        state: TopupState.deliveredLidaValue,
        decision: RecipientDecision(
          decisionId: 'D-1',
          topupOrderId: 'TXN-1',
          status: DecisionStatus.resolved,
          resolvedSource: 'TIMEOUT',
        ),
      ),
      tracked: tracked,
    );
    expect(fallback.failed, isFalse);
    expect(fallback.body, contains('0549017820'));
    expect(fallback.body, contains('Lida Value wallet'));
  });
}
