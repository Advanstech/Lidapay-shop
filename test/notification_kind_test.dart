import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/features/notifications/data/notification_models.dart';

/// Kind classification must match whole words — a profile-update message
/// contains "up**data**ted", which previously classified every such row as
/// a data-bundle notification ("Data bundle", wifi icon, history CTA).
void main() {
  AppNotification fromMessage(String message, {String type = 'email'}) {
    return AppNotification.fromApiJson({
      'id': 'n1',
      'type': type,
      'message': message,
      'status': 'sent',
      'createdAt': '2026-10-20T22:50:00.000Z',
    });
  }

  test('profile updates classify as security, not data', () {
    final n = fromMessage('Your profile has been updated successfully.');
    expect(n.kind, 'security');
    expect(n.displayTitle, 'Security alert');

    final withPayload = fromMessage(
      'Your profile has been updated successfully. Details: '
      '{"_id":"696d454f","password":"\$2b\$10\$xyz","gravatar":"data:image/png;base64,iVBOR"}',
    );
    expect(withPayload.kind, 'security');
    expect(withPayload.displayTitle, 'Security alert');
  });

  test('real data-bundle events still classify as data', () {
    expect(fromMessage('Your data bundle was delivered.').kind, 'data');
    expect(fromMessage('Data bundle sent to 2335551234.').kind, 'data');
  });

  test('airtime and wallet keywords stay word-boundary safe', () {
    expect(fromMessage('Airtime top-up delivered.').kind, 'airtime');
    expect(
      fromMessage('Your appointment is confirmed for Friday.').kind,
      'general',
    );
    expect(fromMessage('Lida Value credited.').kind, 'wallet');
  });

  test('decision rows win over keyword guesses', () {
    final n = AppNotification.fromApiJson({
      'id': 'n2',
      'type': 'push',
      'eventType': 'recipient_topup_decision',
      'decisionId': 'DEC-1',
      'message': 'Someone sent you data.',
      'createdAt': '2026-10-20T22:50:00.000Z',
    });
    expect(n.kind, 'decision');
    expect(n.needsAction, isTrue);
  });
}
