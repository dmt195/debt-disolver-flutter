import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const avalanche = Strategy.avalanche();

  PayoffResult run(List<Debt> debts, int budget, [Strategy s = avalanche]) =>
      calculate(debts: debts, monthlyBudget: gbp(budget), strategy: s);

  group('calculate — synthetic strategies', () {
    final debts = [
      debt(
        id: 'x',
        name: 'Alpha',
        balance: 100000,
        aprBps: 1800,
        minPaymentFloor: 2500,
      ),
      debt(
        id: 'y',
        name: 'Beta',
        balance: 100000,
        aprBps: 1850,
        minPaymentFloor: 2500,
      ),
    ];

    test('consolidation replaces all debts with one fixed-payment loan', () {
      final plan = planOf(
        run(debts, 30000, const Strategy.consolidation(aprBps: 400)),
      );
      expect(plan.payoffOrder, [kConsolidationDebtId]);
      expect(plan.debts.single.startingBalance, gbp(200000));
      expect(plan.months.first.payments, [gbp(30000)]);
      expect(plan.totalFees, gbp(0));
    });

    test(
      'balance transfer adds the fee and is interest-free for the promo period',
      () {
        final plan = planOf(
          run(
            [debt(id: 'a', balance: 1000000, minPaymentFloor: 2500)],
            50000,
            const Strategy.balanceTransfer(
              feeBps: 400,
              promoMonths: 15,
              revertAprBps: 1500,
            ),
          ),
        );
        expect(plan.payoffOrder, [kBalanceTransferDebtId]);
        expect(plan.debts.single.startingBalance, gbp(1040000));
        expect(plan.totalFees, gbp(40000));
        for (final row in plan.months.take(15)) {
          expect(row.interest, [gbp(0)], reason: 'month ${row.month}');
        }
        // Legacy off-by-one gave 16 free months; interest now starts in
        // month 16.
        expect(plan.months[15].interest.single.isPositive, isTrue);
      },
    );
  });

  test('calculateAll returns one result per standard strategy, in order', () {
    final results = calculateAll(
      debts: [debt(id: 'a', balance: 100000)],
      monthlyBudget: gbp(25000),
      parameters: const StrategyParameters(),
    );
    expect(results.map((r) => r.strategyId), StrategyId.values);
  });
}
