import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/core/utils/ghana_networks.dart';

void main() {
  group('GhanaNetworks', () {
    test('MTN prefixes map to code 4 in every typed shape', () {
      for (final n in [
        '0244588584',
        '244588584',
        '233244588584',
        '+233 24 458 8584',
        '0541234567',
        '0551234567',
        '0591234567',
        '0531234567',
        '0251234567',
      ]) {
        expect(GhanaNetworks.codeForNumber(n), '4', reason: n);
        expect(GhanaNetworks.brandForNumber(n), 'MTN', reason: n);
      }
    });

    test('Telecel, AirtelTigo and Glo are never confused with MTN', () {
      expect(GhanaNetworks.codeForNumber('0201234567'), '6');
      expect(GhanaNetworks.codeForNumber('0501234567'), '6');
      expect(GhanaNetworks.codeForNumber('0261234567'), '1');
      expect(GhanaNetworks.codeForNumber('0271234567'), '1');
      expect(GhanaNetworks.codeForNumber('0561234567'), '1');
      expect(GhanaNetworks.codeForNumber('0571234567'), '1');
      expect(GhanaNetworks.codeForNumber('0231234567'), '3');
    });

    test('short or unknown input does not guess', () {
      expect(GhanaNetworks.codeForNumber('02'), isNull);
      expect(GhanaNetworks.codeForNumber('0991234567'), isNull);
    });

    test('provider names resolve by brand', () {
      expect(GhanaNetworks.codeForName('MTN Ghana'), '4');
      expect(GhanaNetworks.codeForName('Telecel Ghana'), '6');
      expect(GhanaNetworks.codeForName('Vodafone Ghana'), '6');
      expect(GhanaNetworks.codeForName('AirtelTigo Ghana'), '1');
      expect(GhanaNetworks.codeForName('MTN Yellow'), '13');
      expect(GhanaNetworks.codeForName('TiGO Ghana'), '5');
      expect(GhanaNetworks.codeForName('Expresso'), '2');
      expect(GhanaNetworks.codeForName('Glo Ghana'), '3');
      expect(GhanaNetworks.codeForName('Busy'), '8');
      expect(GhanaNetworks.codeForName('Surfline'), '9');
      expect(GhanaNetworks.codeForName('Some Unknown Operator'), isNull);
    });

    test('network codes resolve back to display names', () {
      expect(GhanaNetworks.nameForCode('0'), 'Auto Detect');
      expect(GhanaNetworks.nameForCode('1'), 'AirtelTigo');
      expect(GhanaNetworks.nameForCode('2'), 'Expresso');
      expect(GhanaNetworks.nameForCode('3'), 'Glo Ghana');
      expect(GhanaNetworks.nameForCode('4'), 'MTN Ghana');
      expect(GhanaNetworks.nameForCode('5'), 'TiGO');
      expect(GhanaNetworks.nameForCode('6'), 'Telecel Ghana');
      expect(GhanaNetworks.nameForCode('8'), 'Busy');
      expect(GhanaNetworks.nameForCode('9'), 'Surfline');
      expect(GhanaNetworks.nameForCode('13'), 'MTN Yellow');
      expect(GhanaNetworks.nameForCode('99'), isNull);
      expect(GhanaNetworks.brandToCode['MTN YELLOW'], GhanaNetworks.mtnYellow);
    });
  });
}
