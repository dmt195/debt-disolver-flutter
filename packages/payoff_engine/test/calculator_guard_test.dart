import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  PayoffResult run(List<Debt> debts, int budget) => calculate(
    debts: debts,
    monthlyBudget: gbp(budget),
    strategy: const Strategy.avalanche(),
  );

  group('calculate rejects unvalidated input', () {
    test('a negative balance cannot cancel out a real debt', () {
      final debts = [
        debt(id: 'a', balance: 10000),
        debt(id: 'b', balance: -10000),
      ];
      expect(() => run(debts, 5000), throwsArgumentError);
    });

    test('duplicate debt ids', () {
      final debts = [debt(id: 'a', balance: 100), debt(id: 'a', balance: 100)];
      expect(() => run(debts, 5000), throwsArgumentError);
    });

    test('more than kMaxDebts debts', () {
      final debts = [
        for (var i = 0; i <= kMaxDebts; i++) debt(id: 'd$i', balance: 100),
      ];
      expect(() => run(debts, 5000), throwsArgumentError);
    });

    test('a negative budget', () {
      expect(() => run([debt(id: 'a', balance: 100)], -1), throwsArgumentError);
    });
  });

  test('a zero budget is allowed and is infeasible', () {
    final result = run([debt(id: 'a', balance: 100, minPaymentFloor: 10)], 0);
    expect(result, isA<Infeasible>());
  });

  test('the maximum portfolio consolidates without overflow', () {
    final debts = [
      for (var i = 0; i < kMaxDebts; i++)
        debt(id: 'd$i', balance: kMaxAmountMinor, aprBps: 10000),
    ];
    final result = calculate(
      debts: debts,
      monthlyBudget: gbp(kMaxAmountMinor),
      strategy: const Strategy.consolidation(aprBps: 10000),
    );
    // The 60-month payment alone is far above the budget.
    expect(result, isA<Infeasible>());
  });
}
