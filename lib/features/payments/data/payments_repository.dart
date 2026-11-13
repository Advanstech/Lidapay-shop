import 'payment_models.dart';

abstract class PaymentsRepository {
  /// POST /api/v1/advansispay/initiate-payment — creates the Advansis Pay /
  /// ExpressPay checkout. `returnUrl` is intentionally not sent: the backend
  /// builds the `lidapay://` native callback when it is omitted. [redirectUrl]
  /// is the shop contract's mobile deep link (`lidapay://shop/checkout/callback`)
  /// and is only sent for shop orders.
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
  });

  /// POST /api/v1/advansispay/query-transaction — the authoritative check.
  /// [token] is the saved initiation token, never the deep-link value.
  Future<PaymentQueryResult> queryTransaction(String token);

  /// POST /api/v1/gtpay/pay with `ServiceName: debitwallet` — requests a
  /// debit from the customer's MoMo number. [partnerTransId] is generated
  /// and persisted by the caller before this call so a timeout can be
  /// reconciled through [gtPayStatus] without paying twice.
  Future<GtPayResult> gtPayDebit({
    required String partnerTransId,
    required String userId,
    required String userName,
    required String momoNumber,
    required double amount,
    required String remarks,
    required String paidBy,
    String? shopOrderNumber,
  });

  /// POST /api/v1/gtpay/status — the authoritative GTPay outcome.
  Future<GtPayResult> gtPayStatus(String partnerTransId);
}
