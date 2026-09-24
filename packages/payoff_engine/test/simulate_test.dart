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
      ),
    );
    expect(plan.totalFees, gbp(40));
    expect(plan.totalPaid, gbp(1040));
  });
}
