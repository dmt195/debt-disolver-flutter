import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const avalanche = Strategy.avalanche();

  PayoffResult run(List<Debt> debts, int budget, [Strategy s = avalanche]) =>
      calculate(debts: debts, monthlyBudget: gbp(budget), strategy: s);

  group('calculate — monthly mechanics', () {
    test('clears an interest-free debt in budget-sized steps', () {
      final plan = planOf(run([debt(id: 'a', balance: 100000)], 25000));
      expect(plan.monthsToClear, 4);
      expect(plan.totalPaid, gbp(100000));
      expect(plan.totalInterest, gbp(0));
      expect(plan.months.last.closingBalances, [gbp(0)]);
    });

    test('adds interest before paying, rounded half-even to the penny', () {
      // 1200.00 at 12% APR: 1% a month = 12.00; then 100.00 paid.
      final plan = planOf(
        run([debt(id: 'a', balance: 120000, aprBps: 1200)], 10000),
      );
      final first = plan.months.first;
      expect(first.month, 1);
      expect(first.interest, [gbp(1200)]);
      expect(first.payments, [gbp(10000)]);
      expect(first.closingBalances, [gbp(111200)]);
      // Month 2: 1112.00 * 1% = 11.12.
      expect(plan.months[1].interest, [gbp(1112)]);
    });

    test('the final payment is only what is owed', () {
      final plan = planOf(run([debt(id: 'a', balance: 30000)], 25000));
      expect(plan.months.last.payments, [gbp(5000)]);
      expect(plan.totalPaid, gbp(30000));
    });

    test('pays every minimum, then overpays in priority order', () {
      final plan = planOf(
        run([
          debt(id: 'low', balance: 50000, aprBps: 1200, minPaymentFloor: 1000),
          debt(id: 'high', balance: 50000, aprBps: 2400, minPaymentFloor: 1000),
        ], 10000),
      );
      expect(plan.payoffOrder, ['high', 'low']);
      // Month 1: minimums 10.00 each; the remaining 80.00 goes to 'high'.
      expect(plan.months.first.payments, [gbp(9000), gbp(1000)]);
    });

    test('the minimum is the larger of the floor and the percentage', () {
      final plan = planOf(
        run([
          debt(
            id: 'a',
            balance: 100000,
            minPaymentPercentBps: 300,
            minPaymentFloor: 2500,
            allowsOverpayment: false,
          ),
        ], 10000),
      );
      expect(plan.months[0].payments, [gbp(3000)]); // 3% of 1000.00
      // Once 3% falls below 25.00, the floor applies.
      final floorMonth = plan.months.firstWhere(
        (r) => r.payments.single == gbp(2500),
      );
      expect(floorMonth.month, greaterThan(1));
    });

    test('non-overpayable debts get only their minimum', () {
      final plan = planOf(
        run([
          debt(
            id: 'loan',
            balance: 30000,
            minPaymentFloor: 10000,
            allowsOverpayment: false,
          ),
        ], 50000),
      );
      expect(plan.months.first.payments, [gbp(10000)]);
      expect(plan.monthsToClear, 3);
    });

    test('money freed by clearing a debt moves on in the same month', () {
      final plan = planOf(
        run([
          debt(id: 'a', name: 'A', balance: 3000, aprBps: 2000),
          debt(id: 'b', name: 'B', balance: 50000, aprBps: 1000),
        ], 10000),
      );
      // Month 1: A (30.00 + 0.50 interest) is cleared; the other 69.50
      // goes to B.
      final first = plan.months.first;
      expect(first.payments[0], gbp(3050));
      expect(first.payments[1], gbp(6950));
      expect(first.closingBalances[0], gbp(0));
    });

    test('does not modify the input list or its order', () {
      final input = [
        debt(id: 'low', balance: 1000, aprBps: 100),
        debt(id: 'high', balance: 1000, aprBps: 2000),
      ];
      final copy = [...input];
      run(input, 500, const Strategy.snowball());
      run(input, 500);
      expect(input, copy);
    });

    test('rejects debts in a different currency from the budget', () {
      final usd = debt(
        id: 'a',
        balance: 1000,
      ).copyWith(balance: const Money(1000, 'USD'));
      expect(() => run([usd], 500), throwsArgumentError);
    });

    test('no debts gives an empty feasible plan', () {
      for (final s in standardStrategies(const StrategyParameters())) {
        final plan = planOf(run([], 10000, s));
        expect(plan.monthsToClear, 0);
        expect(plan.debts, isEmpty);
        expect(plan.totalPaid, gbp(0));
      }
    });
  });

  group('calculate — strategies', () {
    int col(PayoffPlan p, String id) => p.debts.indexWhere((d) => d.id == id);

    test('avalanche gives a 0% promo debt only its minimum until it ends', () {
      final plan = planOf(
        run([
          debt(
            id: 'a',
            balance: 100000,
            aprBps: 3000,
            promo: const Promo(aprBps: 0, months: 2),
          ),
          debt(id: 'b', balance: 100000, aprBps: 1000),
        ], 10000),
      );
      final a = col(plan, 'a');
      expect(
        [for (final r in plan.months.take(3)) r.payments[a]],
        [gbp(0), gbp(0), gbp(10000)],
      );
      expect(plan.months[2].interest[a], gbp(2500)); // 30% / 12 of 1,000.00
    });

    test('snowball pays the smallest starting balance first', () {
      final plan = planOf(
        run(
          [
            debt(id: 'a', balance: 50000, aprBps: 2000),
            debt(id: 'b', balance: 30000, aprBps: 500),
          ],
          10000,
          const Strategy.snowball(),
        ),
      );
      expect(plan.months.first.payments[col(plan, 'b')], gbp(10000));
      expect(plan.payoffOrder, ['b', 'a']);
      expect(plan.monthsToClear, 9);
      expect(plan.totalPaid, gbp(85737));
    });

    test('custom order follows the list', () {
      final plan = planOf(
        run(
          [
            debt(id: 'a', balance: 50000, aprBps: 500),
            debt(id: 'b', balance: 30000, aprBps: 2000),
          ],
          10000,
          const Strategy.customOrder(),
        ),
      );
      expect(plan.months.first.payments[col(plan, 'a')], gbp(10000));
      expect(plan.payoffOrder, ['a', 'b']);
      expect(plan.totalPaid, gbp(84467));
    });
  });

  group('calculateBaseline', () {
    test('pays only the minimums', () {
      final result = calculateBaseline(
        debts: [debt(id: 'a', balance: 100000, minPaymentFloor: 10000)],
        monthlyBudget: gbp(50000),
      );
      expect(result.strategyId, StrategyId.minimumsOnly);
      expect(planOf(result).monthsToClear, 10);
    });

    test('never clears when the minimum only covers the interest', () {
      // 2% of the balance a month against 24% APR (2% a month).
      final result = calculateBaseline(
        debts: [
          debt(
            id: 'a',
            balance: 100000,
            aprBps: 2400,
            minPaymentPercentBps: 200,
          ),
        ],
        monthlyBudget: gbp(50000),
      );
      expect(
        result,
        const PayoffResult.neverClears(strategyId: StrategyId.minimumsOnly),
      );
    });
  });

  group('calculate — month cap', () {
    test('never clears when a debt is never paid down', () {
      final result = run([
        debt(id: 'a', balance: 1000, allowsOverpayment: false),
      ], 50000);
      expect(
        result,
        const PayoffResult.neverClears(strategyId: StrategyId.avalanche),
      );
    });
  });
}
