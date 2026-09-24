import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('minimumPayment', () {
    test('is the percentage when it exceeds the floor', () {
      final d = debt(
        id: 'a',
        balance: 200000,
        minPaymentPercentBps: 300,
        minPaymentFloor: 2500,
      );
      expect(minimumPayment(d), gbp(6000));
    });

    test('is the floor when it exceeds the percentage', () {
      final d = debt(
        id: 'a',
        balance: 50000,
        minPaymentPercentBps: 300,
        minPaymentFloor: 2500,
      );
      expect(minimumPayment(d), gbp(2500));
    });

    test('never exceeds the balance', () {
      final d = debt(id: 'a', balance: 1000, minPaymentFloor: 2500);
      expect(minimumPayment(d), gbp(1000));
    });

    test('rounds the percentage half to even', () {
      // 3% of 12.50 = 0.375 → 0.38 (pence 37.5 rounds to 38, the even one).
      final d = debt(id: 'a', balance: 1250, minPaymentPercentBps: 300);
      expect(minimumPayment(d), gbp(38));
    });
  });

  test('totalMinimumPayments sums every debt', () {
    final debts = [
      debt(id: 'a', balance: 50000, minPaymentFloor: 2500),
      debt(id: 'b', balance: 200000, minPaymentPercentBps: 300),
    ];
    expect(totalMinimumPayments(debts, currency: 'GBP'), gbp(8500));
    expect(totalMinimumPayments(const [], currency: 'GBP'), gbp(0));
  });
}
