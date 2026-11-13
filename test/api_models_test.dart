import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/features/auth/data/auth_models.dart';
import 'package:lidapay_app/features/dashboard/data/dashboard_models.dart';

void main() {
  group('Transaction.fromApiJson', () {
    test('maps a live row with documented keys', () {
      final t = Transaction.fromApiJson({
        '_id': '66f6d18f',
        'transId': 'TRX-987654',
        'transType': 'DATA',
        'status': 'SUCCESS',
        'amount': 55,
        'currency': 'GHS',
        'createdAt': '2026-10-14T09:30:00.000Z',
        'recipientNumber': '233501234567',
        'description': 'Telecel 5GB',
      });

      expect(t.id, '66f6d18f');
      expect(t.reference, 'TRX-987654');
      expect(t.type, TransactionType.data);
      expect(t.status, TransactionStatus.success);
      expect(t.amount, 55);
      expect(t.currency, 'GHS');
      expect(t.createdAt, DateTime.parse('2026-10-14T09:30:00.000Z'));
      expect(t.counterparty, '233501234567');
      expect(t.description, 'Telecel 5GB');
    });

    test('tolerates alternate key spellings and unknown types', () {
      final t = Transaction.fromApiJson({
        'id': 'x1',
        'trxn': 'TRX-1',
        'type': 'MOBILE_MONEY',
        'status': 'FAILED',
        'transAmount': '12.5',
        'date': '2026-10-14T09:30:00.000Z',
      });

      expect(t.id, 'x1');
      expect(t.reference, 'TRX-1');
      expect(t.type, TransactionType.other);
      expect(t.status, TransactionStatus.failed);
      expect(t.amount, 12.5);
      expect(t.currency, 'GHS'); // default when absent
    });

    test('survives an empty payload', () {
      final t = Transaction.fromApiJson({});
      expect(t.type, TransactionType.other);
      expect(t.status, TransactionStatus.pending);
      expect(t.amount, 0);
    });

    test('flags decision_pending service leg as awaiting recipient', () {
      final t = Transaction.fromApiJson({
        '_id': '66f6d18f',
        'trxn': 'TRX-PARKED',
        'transType': 'AIRTIME',
        'status': {
          'transaction': 'pending',
          'service': 'decision_pending',
          'payment': 'pending',
        },
        'amount': 10,
        'recipientNumber': '233244588584',
      });

      expect(t.status, TransactionStatus.pending);
      expect(t.isAwaitingRecipientDecision, isTrue);
    });

    test('plain pending transaction is not awaiting a decision', () {
      final t = Transaction.fromApiJson({
        '_id': '66f6d190',
        'trxn': 'TRX-NORMAL',
        'transType': 'DATA',
        'status': {
          'transaction': 'pending',
          'service': 'pending',
          'payment': 'pending',
        },
        'amount': 5,
      });

      expect(t.status, TransactionStatus.pending);
      expect(t.isAwaitingRecipientDecision, isFalse);
    });
  });

  group('TransactionType.fromApi', () {
    test('maps the known live transTypes', () {
      expect(TransactionType.fromApi('AIRTIME'), TransactionType.airtime);
      expect(TransactionType.fromApi('airtime'), TransactionType.airtime);
      expect(TransactionType.fromApi('DATA'), TransactionType.data);
      expect(TransactionType.fromApi('SHOP_ORDER'), TransactionType.shopOrder);
      expect(TransactionType.fromApi('LIDA_VALUE'), TransactionType.lidaValue);
      expect(
        TransactionType.fromApi('WALLET_TOPUP'),
        TransactionType.walletTopUp,
      );
    });
  });

  group('AuthTokens.fromJson', () {
    test('reads the live snake_case keys', () {
      final tokens = AuthTokens.fromJson({
        'access_token': 'acc',
        'refresh_token': 'ref',
      });
      expect(tokens.accessToken, 'acc');
      expect(tokens.refreshToken, 'ref');
    });
  });

  group('UserProfile.fromJson', () {
    test('prefers profile fields and falls back to username for phone', () {
      final user = UserProfile.fromJson({
        '_id': '6749f104',
        'firstName': 'John',
        'lastName': 'Doe',
        'email': 'john@example.com',
        'username': '0244588584',
        'country': 'Ghana',
        'emailVerified': true,
        'phoneVerified': 'true',
        'status': 'ACTIVE',
      });
      expect(user.id, '6749f104');
      expect(user.fullName, 'John Doe');
      expect(user.phoneNumber, '0244588584');
      expect(user.username, '0244588584');
      expect(user.emailVerified, isTrue);
      expect(user.phoneVerified, isTrue);
      expect(user.isVerified, isTrue);
    });
  });

  group('ProfileUpdateRequest', () {
    test('only sends user-editable fields', () {
      const request = ProfileUpdateRequest(
        firstName: 'Kofi',
        lastName: 'Annan',
        email: 'kofi@example.com',
        phoneNumber: '0241111111',
      );
      expect(request.toJson(), {
        'firstName': 'Kofi',
        'lastName': 'Annan',
        'email': 'kofi@example.com',
        'phoneNumber': '0241111111',
      });
    });
  });
}
