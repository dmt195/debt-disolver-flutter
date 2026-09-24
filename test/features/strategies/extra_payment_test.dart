import 'package:debt_destroyer/features/strategies/domain/extra_payment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  test('about 60 round steps across the budget', () {
    expect(extraPaymentStepMinor(const Money(30000, 'GBP')), 500); // £5
    expect(extraPaymentStepMinor(const Money(100000, 'GBP')), 2000); // £20
    expect(extraPaymentStepMinor(const Money(1234500, 'GBP')), 50000); // £500
  });

  test('never below one major unit', () {
    expect(extraPaymentStepMinor(const Money(5000, 'GBP')), 100); // £1
  });

  test('works in currencies without decimals', () {
    expect(extraPaymentStepMinor(const Money(30000, 'JPY')), 500); // ¥500
  });

  group('effectiveExtraMinor', () {
    test('clamps to the nearest step at or below the budget', () {
      // Step 500 (see above), so the max whole step below 19,950 is 19,500.
      expect(effectiveExtraMinor(20000, const Money(19950, 'GBP')), 19500);
    });

    test('never negative', () {
      expect(effectiveExtraMinor(-100, const Money(30000, 'GBP')), 0);
    });

    test('unchanged within range', () {
      expect(effectiveExtraMinor(5000, const Money(30000, 'GBP')), 5000);
    });
  });
}
