import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('spends extra money in list order', () {
    final plan = planOf(
      simulate(
        strategyId: StrategyId.avalanche,
        debts: [
          debt(id: 'first', balance: 50000, aprBps: 500),
          debt(id: 'second', balance: 50000, aprBps: 2000),
        ],
        budget: gbp(10000),
        fees: gbp(0),
        order: (_) => [0, 1],
      ),
    );
    expect(plan.months.first.payments, [gbp(10000), gbp(0)]);
  });

  test('reports the fees it is given', () {
    final plan = planOf(
      simulate(
        strategyId: StrategyId.balanceTransfer,
        debts: [debt(id: 'a', balance: 1040)],
        budget: gbp(1040),
        fees: gbp(40),
        order: (_) => [0],
      ),
    );
    expect(plan.totalFees, gbp(40));
    expect(plan.totalPaid, gbp(1040));
  });

  test('lists debts in the order they are cleared', () {
    // The loan's fixed 100.00 clears it in month 2; the card takes longer.
    final plan = planOf(
      simulate(
        strategyId: StrategyId.avalanche,
        debts: [
          debt(id: 'high', balance: 100000, aprBps: 2000),
          debt(
            id: 'loan',
            balance: 20000,
            minPaymentFloor: 10000,
            allowsOverpayment: false,
          ),
        ],
        budget: gbp(30000),
        fees: gbp(0),
        order: (_) => [0, 1],
      ),
    );
    expect(plan.payoffOrder, ['loan', 'high']);
    // Columns follow the same order: the loan's minimum, then the rest.
    expect(plan.months.first.payments, [gbp(10000), gbp(20000)]);
    expect(plan.monthsToClear, 5);
    expect(plan.totalPaid, gbp(124723));
  });

  test(
    "debts clearing in the same month keep that month's allocation order",
    () {
      // Both debts clear within month 1; the tie is broken by the order the
      // budget was allocated in that month, not by list order.
      final plan = planOf(
        simulate(
          strategyId: StrategyId.avalanche,
          debts: [
            debt(id: 'a', balance: 1000, aprBps: 500),
            debt(id: 'b', balance: 1000, aprBps: 2000),
          ],
          budget: gbp(5000),
          fees: gbp(0),
          order: (_) => [1, 0],
        ),
      );
      expect(plan.payoffOrder, ['b', 'a']);
    },
  );

  test('with allowExtra false, pays only the minimums', () {
    final plan = planOf(
      simulate(
        strategyId: StrategyId.minimumsOnly,
        debts: [debt(id: 'a', balance: 100000, minPaymentFloor: 10000)],
        budget: gbp(50000),
        fees: gbp(0),
        order: (_) => [0],
        allowExtra: false,
      ),
    );
    expect(plan.monthsToClear, 10);
    expect(plan.months.every((r) => r.payments.single == gbp(10000)), isTrue);
  });
}
