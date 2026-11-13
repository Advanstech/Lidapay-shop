import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/core/utils/validators.dart';

void main() {
  group('Validators.phone', () {
    test('accepts Ghana format 0xxxxxxxx', () {
      expect(Validators.phone('0244588584'), isNull);
    });

    test('rejects short or non-Ghana numbers', () {
      expect(Validators.phone('244588584'), isNotNull);
      expect(Validators.phone('02445885845'), isNotNull);
      expect(Validators.phone(''), isNotNull);
    });
  });

  group('Validators.email', () {
    test('accepts valid emails', () {
      expect(Validators.email('ama@example.com'), isNull);
    });

    test('rejects invalid emails', () {
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email(''), isNotNull);
    });
  });

  group('PasswordStrength.of', () {
    test('empty password scores empty', () {
      expect(PasswordStrength.of(''), PasswordStrength.empty);
    });

    test('short simple password is weak', () {
      expect(PasswordStrength.of('abc'), PasswordStrength.weak);
    });

    test('long mixed password is strong', () {
      expect(PasswordStrength.of('Str0ng!Passw0rd'), PasswordStrength.strong);
    });
  });
}
