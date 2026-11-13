import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import 'payment_models.dart';
import 'payments_repository.dart';

class RemotePaymentsRepository implements PaymentsRepository {
  RemotePaymentsRepository(this._api);

  final ApiClient _api;

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
    final body = await _api.post(
      ApiEndpoints.advansisInitiate,
      body: {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phoneNumber': phoneNumber,
        'username': username,
        'userId': userId,
        'amount': amount,
        'orderDesc': orderDesc,
        'transType': transType,
        if (payTransRef != null) 'payTransRef': payTransRef,
        if (shopOrderNumber != null) 'shopOrderNumber': shopOrderNumber,
        if (redirectUrl != null) 'redirectUrl': redirectUrl,
      },
    );
    final initiation = PaymentInitiation.fromJson(body);
    if (!initiation.isUsable) {
      throw const ApiException(
        'The payment service did not return a checkout page. '
        'Please try again.',
        code: 'INITIATE_MALFORMED',
      );
    }
    return initiation;
  }

  @override
  Future<PaymentQueryResult> queryTransaction(String token) async {
    final body = await _api.post(
      ApiEndpoints.advansisQuery,
      body: {'token': token},
    );
    return PaymentQueryResult.fromJson(body);
  }

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
    final body = await _api.post(
      ApiEndpoints.gtPayPay,
      body: {
        'PartnerTransId': partnerTransId,
        'userId': userId,
        'userName': userName,
        if (shopOrderNumber != null) 'shopOrderNumber': shopOrderNumber,
        'ServiceDetails': {
          'ServiceName': 'debitwallet',
          'ServiceNumber': momoNumber,
          'SecondaryServiceNumber': '',
          'Amount': amount.toStringAsFixed(2),
          'Remarks': remarks,
          'PaidBy': paidBy,
          'PayeeName': 'Lidapay',
        },
      },
    );
    return GtPayResult.fromJson(body);
  }

  @override
  Future<GtPayResult> gtPayStatus(String partnerTransId) async {
    final body = await _api.post(
      ApiEndpoints.gtPayStatus,
      body: {'PartnerTransId': partnerTransId},
    );
    return GtPayResult.fromJson(body);
  }
}
