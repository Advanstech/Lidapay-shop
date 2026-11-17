import 'package:flutter/services.dart';

/// Formats recipient phone input for airtime and data services.
///
/// Strips non-digit characters (spaces, dashes, parentheses), eliminates
/// redundant leading dial codes (e.g. +234 or 234 when Nigeria is selected),
/// normalises Ghana subscriber numbers to 9 digits, and notifies on international paste.
class PhoneNumberInputFormatter extends TextInputFormatter {
  final String dialCode;
  final String isoCode;
  final void Function(String raw)? onInternationalPaste;

  PhoneNumberInputFormatter({
    required this.dialCode,
    required this.isoCode,
    this.onInternationalPaste,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Detect pasted international number starting with + or 00
    if ((newValue.text.startsWith('+') || newValue.text.startsWith('00')) &&
        onInternationalPaste != null) {
      final raw = newValue.text;
      onInternationalPaste!(raw);
    }

    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final dialDigits = dialCode.replaceAll(RegExp(r'\D'), '');

    // Strip leading 00 + dialDigits if present
    if (dialDigits.isNotEmpty && digits.startsWith('00$dialDigits')) {
      digits = digits.substring(2 + dialDigits.length);
    }
    // Strip leading dialDigits only when the input looks like a full
    // international number (so typing a local Glo 0233... number never loses 233).
    else if (dialDigits.isNotEmpty &&
        digits.startsWith(dialDigits) &&
        (isoCode != 'GH'
            ? digits.length > dialDigits.length + 6
            : digits.length >= dialDigits.length + 9)) {
      digits = digits.substring(dialDigits.length);
    }

    // For Ghana, strip leading 0 if present (e.g. 0244123456 -> 244123456)
    // and cap subscriber digits at 9 so an extra digit can't slip in as 2444...
    if (isoCode == 'GH' && digits.startsWith('0') && digits.length > 1) {
      digits = digits.substring(1);
    }
    if (isoCode == 'GH' && digits.length > 9) {
      digits = digits.substring(0, 9);
    }

    // Cap at 15 digits (ITU-T E.164 max telephone length)
    if (digits.length > 15) {
      digits = digits.substring(0, 15);
    }

    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
