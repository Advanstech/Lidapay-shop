import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  static final _currency = NumberFormat.currency(
    symbol: 'GH₵',
    decimalDigits: 2,
  );
  static final _compact = NumberFormat.compact();
  static final _dateTime = DateFormat('d MMM yyyy, h:mm a');

  static String currency(num amount) => _currency.format(amount);

  /// Currency-aware amount: `GH₵12.00` for GHS rows, `12.00 LV` for
  /// reward-unit rows (Lida Value, Lida Points) so units never masquerade
  /// as cash.
  static String money(num amount, [String currency = 'GHS']) {
    final code = currency.trim().toUpperCase();
    if (code.isEmpty || code == 'GHS' || code == 'GH₵') {
      return _currency.format(amount);
    }
    final value = amount % 1 == 0
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    return '$value $code';
  }

  static String compact(num value) => _compact.format(value);

  static final _points = NumberFormat('#,##0.##');

  /// Wallet points — `1,250.5 PTS`. The wallet is a points balance, not a
  /// fiat account, so it never renders a currency symbol or code.
  static String points(num amount) => '${_points.format(amount)} PTS';

  static String dateTime(DateTime dt) => _dateTime.format(dt.toLocal());

  /// Compact relative time for feed rows (`2h ago`, `3d ago`, …).
  static String timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('d MMM yyyy').format(dt.toLocal());
  }

  static String maskedPhone(String phone) {
    if (phone.length < 7) return phone;
    return '${phone.substring(0, 3)}••••${phone.substring(phone.length - 3)}';
  }

  /// Turns backend failure codes (`INSUFFICIENT_FUNDS`, `DELIVERY_FAILED`,
  /// `OPERATOR_ERROR`…) into a sentence a customer can act on. Reasons that
  /// already arrive as plain sentences pass through untouched.
  static String friendlyFailureReason(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) {
      return 'The transaction could not be completed. If you were charged, '
          'please contact support with your payment reference.';
    }
    final code = text.toUpperCase().replaceAll(RegExp(r'[\s\-]+'), '_');
    const balance =
        'The mobile money wallet did not have enough balance to '
        'complete the payment.';
    const declined = 'The payment was declined on the phone.';
    const expired =
        'The approval prompt expired before it was approved on the phone.';
    const cancelled = 'The payment was cancelled before it completed.';
    const provider =
        'The mobile money network had a problem completing the '
        'transaction. Please try again.';
    const recipient = 'The recipient number could not receive this top-up.';
    const known = <String, String>{
      'INSUFFICIENT_FUNDS': balance,
      'LOW_BALANCE': balance,
      'NOT_ENOUGH_FUNDS': balance,
      'USER_DECLINED': declined,
      'DECLINED': declined,
      'REJECTED': declined,
      'TIMEOUT': expired,
      'PROMPT_EXPIRED': expired,
      'EXPIRED': expired,
      'CANCELLED': cancelled,
      'CANCELED': cancelled,
      'REVERSED': 'The payment was reversed by the network.',
      'DELIVERY_FAILED':
          'The payment went through but the delivery could not '
          'be completed — if you were charged, contact support with the '
          'reference.',
      'INVALID_RECIPIENT': recipient,
      'INVALID_MSISDN': recipient,
      'BARRED': 'The recipient number is barred from receiving top-ups.',
      'PROVIDER_ERROR': provider,
      'OPERATOR_ERROR': provider,
      'UPSTREAM_ERROR': provider,
      'NETWORK_ERROR': 'A network problem interrupted the transaction.',
    };
    for (final entry in known.entries) {
      if (code.contains(entry.key)) return entry.value;
    }
    // A bare SNAKE_CASE code nobody mapped — still humanize the words.
    if (RegExp(r'^[A-Z0-9_\-]+$').hasMatch(text)) {
      final words = text
          .toLowerCase()
          .split(RegExp(r'[_\-]+'))
          .where((w) => w.isNotEmpty)
          .join(' ');
      return 'The transaction failed ($words). If you were charged, '
          'contact support with the reference.';
    }
    return text;
  }
}
