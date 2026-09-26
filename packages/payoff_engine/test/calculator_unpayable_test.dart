import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const avalanche = Strategy.avalanche();

  PayoffResult run(List<Debt> debts, int budget, [Strategy s = avalanche]) =>
      calculate(debts: debts, monthlyBudget: gbp(budget), strategy: s);

  group('calculate — unpayable budgets and overflow', () {
    test('is infeasible when the minimums exceed the budget', () {
      final result = run([
        debt(id: 'a', balance: 100000, aprBps: 1200, minPaymentFloor: 2500),
        debt(id: 'b', balance: 100000, aprBps: 1200, minPaymentFloor: 2500),
      ], 4000);
      expect(
        result,
        PayoffResult.infeasible(
          strategyId: StrategyId.avalanche,
          shortfall: gbp(1000),
          month: 1,
        ),
      );
    });

    // Figures worked out with APR ÷ 12; the subject isn't the rate.
    test(
      'is infeasible in a later month if the minimums grow past the budget',
      () => nominal(() {
        // The minimum (2% of balance) is below the interest (3% a month),
        // so the balance and its minimum both keep growing.
        final result = run([
          debt(
            id: 'a',
            balance: 100000,
            aprBps: 3600,
            minPaymentPercentBps: 200,
            allowsOverpayment: false,
          ),
        ], 2500);
        // Month 22 is the first whose 2% minimum exceeds 25.00: 25.07.
        expect(
          result,
          PayoffResult.infeasible(
            strategyId: StrategyId.avalanche,
            shortfall: gbp(7),
            month: 22,
          ),
        );
      }),
    );

    test('never clears when payments cannot outpace interest', () {
      // 2% a month on 10,000.00 is 200.00; the fixed minimum is 100.00.
      final result = run([
        debt(
          id: 'a',
          balance: 1000000,
          aprBps: 2400,
          minPaymentFloor: 10000,
          allowsOverpayment: false,
        ),
      ], 50000);
      expect(
        result,
        const PayoffResult.neverClears(strategyId: StrategyId.avalanche),
      );
    });

    test('never clears at the maximum inputs without integer overflow', () {
      final result = run([
        debt(
          id: 'a',
          balance: kMaxAmountMinor,
          aprBps: 10000,
          minPaymentFloor: 1,
          allowsOverpayment: false,
        ),
      ], 100);
      expect(
        result,
        const PayoffResult.neverClears(strategyId: StrategyId.avalanche),
      );
    });
  });

  test(
    'under compound interest a growing minimum still runs out of budget',
    () {
      // 36% APR is 2.60% a month, still above the 2% minimum.
      final result = run([
        debt(
          id: 'a',
          balance: 100000,
          aprBps: 3600,
          minPaymentPercentBps: 200,
          allowsOverpayment: false,
        ),
      ], 2500);
      expect(result, isA<Infeasible>());
    },
  );
}
