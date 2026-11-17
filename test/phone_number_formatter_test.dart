import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/features/services/widgets/phone_number_formatter.dart';

void main() {
  group('PhoneNumberInputFormatter', () {
    test('Nigeria: strips redundant +234 when pasted with country code', () {
      final formatter = PhoneNumberInputFormatter(
        dialCode: '+234',
        isoCode: 'NG',
      );

      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '+234 801 234 5678'),
      );

      expect(result.text, equals('8012345678'));
    });

    test('Nigeria: strips redundant 234 when pasted without + sign', () {
      final formatter = PhoneNumberInputFormatter(
        dialCode: '+234',
        isoCode: 'NG',
      );

      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '2348012345678'),
      );

      expect(result.text, equals('8012345678'));
    });

    test('Nigeria: preserves local format starting with 0', () {
      final formatter = PhoneNumberInputFormatter(
        dialCode: '+234',
        isoCode: 'NG',
      );

      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '0801 234 5678'),
      );

      expect(result.text, equals('08012345678'));
    });

    test('Nigeria: normal digit typing is preserved', () {
      final formatter = PhoneNumberInputFormatter(
        dialCode: '+234',
        isoCode: 'NG',
      );

      var value = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '8'),
      );
      expect(value.text, equals('8'));

      value = formatter.formatEditUpdate(
        value,
        const TextEditingValue(text: '80'),
      );
      expect(value.text, equals('80'));

      value = formatter.formatEditUpdate(
        value,
        const TextEditingValue(text: '801'),
      );
      expect(value.text, equals('801'));
    });

    test('Ghana: strips redundant +233 and leading 0 when pasted', () {
      final formatter = PhoneNumberInputFormatter(
        dialCode: '+233',
        isoCode: 'GH',
      );

      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '+233 24 458 8584'),
      );

      expect(result.text, equals('244588584'));
    });

    test('Ghana: normalises local 0244588584 to 9 digits', () {
      final formatter = PhoneNumberInputFormatter(
        dialCode: '+233',
        isoCode: 'GH',
      );

      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '0244 588 584'),
      );

      expect(result.text, equals('244588584'));
    });

    test('International paste triggers callback', () {
      String? pastedRaw;
      final formatter = PhoneNumberInputFormatter(
        dialCode: '+233',
        isoCode: 'GH',
        onInternationalPaste: (raw) => pastedRaw = raw,
      );

      formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '+234 801 234 5678'),
      );

      expect(pastedRaw, equals('+234 801 234 5678'));
    });

    test('Strips 00 international prefix', () {
      final formatter = PhoneNumberInputFormatter(
        dialCode: '+234',
        isoCode: 'NG',
      );

      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '002348012345678'),
      );

      expect(result.text, equals('8012345678'));
    });

    test('Ghana: caps subscriber digits at 9 and preserves 0233 Glo prefix', () {
      final formatter = PhoneNumberInputFormatter(
        dialCode: '+233',
        isoCode: 'GH',
      );

      final capped = formatter.formatEditUpdate(
        const TextEditingValue(text: '244954473'),
        const TextEditingValue(text: '2449544739'),
      );
      expect(capped.text, equals('244954473'));

      final glo = formatter.formatEditUpdate(
        const TextEditingValue(text: '233'),
        const TextEditingValue(text: '2334'),
      );
      expect(glo.text, equals('2334'));
    });
  });
}
