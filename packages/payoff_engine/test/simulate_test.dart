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

  group('cards made of portions', () {
    // One card: its own 100.00 at 12%, and 100.00 moved on at 0% for 12
    // months. The card's minimum is 10% of the card total, with no floor.
    final own = debt(
      id: 'card',
      balance: 10000,
      aprBps: 1200,
      minPaymentPercentBps: 1000,
    );
    final moved = debt(
      id: 'card#from-x',
      balance: 10000,
      aprBps: 1200,
      promo: const Promo(aprBps: 0, months: 12),
    );

    // StrategyId.cardTransfers doesn't exist until Task 3; Task 3 switches
    // these to it when it adds the id.
    PayoffPlan run(int budget) => planOf(
      simulate(
        strategyId: StrategyId.avalanche,
        debts: [own, moved],
        budget: gbp(budget),
        fees: gbp(0),
        order: (_) => [0, 1],
        groups: [
          [0, 1],
        ],
      ),
    );

    int col(PayoffPlan p, String id) => p.debts.indexWhere((d) => d.id == id);

    test('one minimum on the card total, lowest rate first', () {
      // Month 1: own +1.00 interest; card total 201.00; 10% minimum is
      // 20.10, all to the 0% portion. The extra 10.00 goes to the 12% one.
      final plan = run(3010);
      final first = plan.months.first;
      expect(first.interest[col(plan, 'card')], gbp(100));
      expect(first.interest[col(plan, 'card#from-x')], gbp(0));
      expect(first.payments[col(plan, 'card#from-x')], gbp(2010));
      expect(first.payments[col(plan, 'card')], gbp(1000));
    });

    test('the 0% portion is cleared last', () {
      final plan = run(3010);
      expect(plan.payoffOrder, ['card', 'card#from-x']);
    });

    test('the minimums of all cards must fit the budget', () {
      expect(
        simulate(
          strategyId: StrategyId.avalanche,
          debts: [own, moved],
          budget: gbp(2000),
          fees: gbp(0),
          order: (_) => [0, 1],
          groups: [
            [0, 1],
          ],
        ),
        PayoffResult.infeasible(
          strategyId: StrategyId.avalanche,
          shortfall: gbp(10),
          month: 1,
        ),
      );
    });
  });
}
