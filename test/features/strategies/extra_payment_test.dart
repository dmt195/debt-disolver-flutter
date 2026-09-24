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
}
