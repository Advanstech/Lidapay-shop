import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/app.dart';
import 'package:lidapay_app/core/network/token_store.dart';
import 'package:lidapay_app/features/auth/data/mock_auth_repository.dart';
import 'package:lidapay_app/features/auth/providers.dart';
import 'package:lidapay_app/features/dashboard/data/mock_dashboard_repository.dart';
import 'package:lidapay_app/features/dashboard/providers.dart';
import 'package:lidapay_app/features/history/data/mock_history_repository.dart';
import 'package:lidapay_app/features/history/providers.dart';
import 'package:lidapay_app/features/notifications/data/mock_notifications_repository.dart';
import 'package:lidapay_app/features/notifications/providers.dart';
import 'package:lidapay_app/features/payments/data/payment_models.dart';
import 'package:lidapay_app/features/payments/data/payments_repository.dart';
import 'package:lidapay_app/features/payments/providers.dart';
import 'package:lidapay_app/features/recipient_choice/data/recipient_choice_repository.dart';
import 'package:lidapay_app/features/recipient_choice/data/recipient_models.dart';
import 'package:lidapay_app/features/recipient_choice/providers.dart';
import 'package:lidapay_app/features/services/data/mock_services_repository.dart';
import 'package:lidapay_app/features/services/data/services_repository.dart';
import 'package:lidapay_app/features/services/providers.dart';
import 'package:lidapay_app/features/shop/data/mock_shop_repository.dart';
import 'package:lidapay_app/features/shop/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deterministic payments repo for widget tests: every initiation returns a
/// fixed checkout URL/token and every query reports success, so the shared
/// payment session can run end-to-end without a browser or network.
class FakePaymentsRepository implements PaymentsRepository {
  final initiateBodies = <Map<String, dynamic>>[];

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
    return const PaymentInitiation(
      checkoutUrl: 'https://checkout.example/pay/1',
      token: 'saved-token',
      orderId: 'ADV-1',
    );
  }

  @override
  Future<PaymentQueryResult> queryTransaction(String token) async =>
      const PaymentQueryResult(status: 'SUCCESS');

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
  }) async => GtPayResult(status: 'COMPLETED', partnerTransId: partnerTransId);

  @override
  Future<GtPayResult> gtPayStatus(String partnerTransId) async =>
      GtPayResult(status: 'COMPLETED', partnerTransId: partnerTransId);
}

class FakeRecipientChoiceRepository implements RecipientChoiceRepository {
  @override
  Future<RecipientEligibility> checkEligibility({
    required String recipientPhone,
    required String serviceType,
    String? countryIsoCode,
  }) async => const RecipientEligibility.unregistered();

  @override
  Future<List<RecipientDecision>> getPendingDecisions() async => const [];

  @override
  Future<RecipientDecision> getDecision(String decisionId) async =>
      RecipientDecision(
        decisionId: decisionId,
        topupOrderId: 'TRX-MOCK',
        status: DecisionStatus.pending,
      );

  @override
  Future<RecipientDecision> respondToDecision({
    required String decisionId,
    required RecipientChoice choice,
    required String idempotencyKey,
  }) async => RecipientDecision(
    decisionId: decisionId,
    topupOrderId: 'TRX-MOCK',
    status: DecisionStatus.resolved,
    selectedChoice: choice,
  );

  @override
  Future<TopupOrderStatus> getTopupStatus(String topupOrderId) async =>
      TopupOrderStatus(
        topupOrderId: topupOrderId,
        state: TopupState.deliveredDirect,
      );
}

/// Pumps the full app backed by the mock repositories. Call
/// `SharedPreferences.setMockInitialValues` first — production wiring hits
/// the live API, which tests must never touch.
///
/// [services] lets a test swap in a variant of [MockServicesRepository] to
/// exercise a specific provider payload or failure mode.
Future<void> pumpMockApp(
  WidgetTester tester, {
  ServicesRepository? services,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(MockAuthRepository()),
        dashboardRepositoryProvider.overrideWithValue(
          MockDashboardRepository(),
        ),
        historyRepositoryProvider.overrideWithValue(MockHistoryRepository()),
        notificationsRepositoryProvider.overrideWithValue(
          MockNotificationsRepository(),
        ),
        servicesRepositoryProvider.overrideWithValue(
          services ?? MockServicesRepository(),
        ),
        shopRepositoryProvider.overrideWithValue(MockShopRepository()),
        paymentsRepositoryProvider.overrideWithValue(
          FakePaymentsRepository(),
        ),
        recipientChoiceRepositoryProvider.overrideWithValue(
          FakeRecipientChoiceRepository(),
        ),
        checkoutLauncherProvider.overrideWithValue((_) async => true),
      ],
      child: const LidapayApp(),
    ),
  );
}
