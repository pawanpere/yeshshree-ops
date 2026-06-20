import 'package:flutter_test/flutter_test.dart';
import 'package:yeshshree_ops/ui2/validators.dart';

/// Locks in the input-validation rules the product owner chose: hard-block,
/// strict Indian plate, real (>=3-char) names/free-text, etc. The headline case
/// from the bug report — "AB" must NOT be accepted anywhere — is asserted first.
void main() {
  group('the "AB" bug — 2-char junk is rejected everywhere', () {
    test('AB is not a valid plate / name / vendor', () {
      expect(V.plate('AB'), isFalse);
      expect(V.name('AB'), isFalse);
      expect(V.freeText('AB'), isFalse);
    });
  });

  group('vehicle plate (strict Indian)', () {
    test('accepts real plates, spaced or not, any case', () {
      expect(V.plate('MH12AB4421'), isTrue);
      expect(V.plate('mh12 ab 4421'), isTrue);
      expect(V.plate('MH 04 GT 7788'), isTrue);
      expect(V.plate('DL1CAB1234'), isTrue);
    });
    test('rejects junk / partial / non-conforming', () {
      expect(V.plate('AB'), isFalse);
      expect(V.plate('1234'), isFalse);
      expect(V.plate('MH'), isFalse);
      expect(V.plate('asdf'), isFalse);
      expect(V.plate(''), isFalse);
    });
    test('normPlate uppercases and strips spaces', () {
      expect(V.normPlate('mh12 ab 4421'), 'MH12AB4421');
    });
  });

  group('names & free text', () {
    test('require >=3 chars and a letter', () {
      expect(V.name('Ravi'), isTrue);
      expect(V.name('राजू'), isTrue);
      expect(V.name('Om'), isFalse); // 2 chars
      expect(V.name('123'), isFalse); // no letter
      expect(V.freeText('Sandhar Steel'), isTrue);
      expect(V.freeText('AB'), isFalse);
    });
  });

  group('credentials', () {
    test('username charset + length', () {
      expect(V.username('gate1'), isTrue);
      expect(V.username('gate.1_a'), isTrue);
      expect(V.username('ab'), isFalse); // too short
      expect(V.username('Gate1'), isFalse); // uppercase
      expect(V.username('gate 1'), isFalse); // space
    });
    test('password min length + not all-whitespace', () {
      expect(V.password('secret1'), isTrue);
      expect(V.password('abc'), isFalse);
      expect(V.password('      '), isFalse);
    });
    test('PIN is 4 digits and not trivial', () {
      expect(V.pin('5837'), isTrue);
      expect(V.pin('1234'), isFalse);
      expect(V.pin('0000'), isFalse);
      expect(V.pin('12'), isFalse);
    });
  });

  group('codes & numbers', () {
    test('device key is a lowercase slug', () {
      expect(V.deviceKey('gate-kiosk-1'), isTrue);
      expect(V.deviceKey('ab'), isFalse);
      expect(V.deviceKey('Gate_Kiosk'), isFalse);
      expect(V.deviceKey('-bad'), isFalse);
      expect(V.deviceKey('bad--key'), isFalse);
    });
    test('SAP order is >=6 digits', () {
      expect(V.sapOrder('100482'), isTrue);
      expect(V.sapOrder('12345'), isFalse);
      expect(V.sapOrder('abc123'), isFalse);
    });
    test('mobile is 10 digits starting 6-9', () {
      expect(V.mobile('9876543210'), isTrue);
      expect(V.mobile('98765 43210'), isTrue);
      expect(V.mobile('1234567890'), isFalse); // starts 1
      expect(V.mobile('98765'), isFalse);
    });
    test('positive quantity', () {
      expect(V.positive(0.1), isTrue);
      expect(V.positive(0), isFalse);
      expect(V.positive(null), isFalse);
      expect(V.positive(-3), isFalse);
    });
  });
}
