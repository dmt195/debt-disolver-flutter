import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Money', () {
    test('adds and subtracts in minor units', () {
      expect(
        const Money(150, 'GBP') + const Money(25, 'GBP'),
        const Money(175, 'GBP'),
      );
      expect(
        const Money(150, 'GBP') - const Money(200, 'GBP'),
        const Money(-50, 'GBP'),
      );
    });

    test('has value equality including currency', () {
      expect(const Money(100, 'GBP'), const Money(100, 'GBP'));
      expect(const Money(100, 'GBP'), isNot(const Money(100, 'USD')));
    });

    test('compares amounts', () {
      expect(const Money(1, 'GBP') < const Money(2, 'GBP'), isTrue);
      expect(const Money(2, 'GBP') >= const Money(2, 'GBP'), isTrue);
      expect(const Money(3, 'GBP').compareTo(const Money(2, 'GBP')), 1);
    });

    test('rejects arithmetic across currencies', () {
      expect(
        () => const Money(1, 'GBP') + const Money(1, 'USD'),
        throwsArgumentError,
      );
      expect(
        () => const Money(1, 'GBP') < const Money(1, 'USD'),
        throwsArgumentError,
      );
    });

    test('reports sign', () {
      expect(const Money.zero('GBP').isZero, isTrue);
      expect(const Money(1, 'GBP').isPositive, isTrue);
      expect(const Money(-1, 'GBP').isNegative, isTrue);
    });
  });
}
