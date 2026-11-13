import 'package:flutter/material.dart';

/// Shared confirmation for any change of funding source on a Lida
/// Value-funded airtime/data run.
///
/// SEND and USE are Lida Value menu actions, so the Lida Value wallet is what
/// pays. Leaving that rail — or returning to it — changes how the user is
/// charged, so it must be acknowledged rather than flipped silently. Cancel
/// (or dismissing the dialog) always keeps the current funding.
Future<bool> _confirmFundingSwitch(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Offered when the Lida Value balance cannot cover the amount: move the
/// purchase onto the standard airtime/data checkout, charged in mobile money
/// or with an Advansis Pay debit/credit card.
Future<bool> confirmStandardCheckoutSwitch(
  BuildContext context, {
  required String serviceLabel,
}) => _confirmFundingSwitch(
  context,
  title: 'Switch to mobile money or card?',
  message:
      'This $serviceLabel purchase is paid from your Lida Value wallet, but '
      'your balance is below the amount. Switching moves it to the normal '
      'airtime and data checkout, where you are charged in mobile money or an '
      'Advansis Pay debit or credit card instead. Your Lida Value balance '
      'stays untouched.',
  confirmLabel: 'Switch payment',
);

/// Offered after a shortfall detour: go back to debiting the Lida Value
/// wallet instead of mobile money or a card.
Future<bool> confirmLidaValueRestore(
  BuildContext context, {
  required String serviceLabel,
  required String balanceLabel,
}) => _confirmFundingSwitch(
  context,
  title: 'Switch back to Lida Value?',
  message:
      'This $serviceLabel purchase will be debited from your Lida Value '
      'wallet ($balanceLabel available) instead of mobile money or a card. '
      'The debit is rejected if the balance cannot cover the amount.',
  confirmLabel: 'Use Lida Value',
);
