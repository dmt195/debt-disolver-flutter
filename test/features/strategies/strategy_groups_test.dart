import 'package:debt_destroyer/features/strategies/domain/strategy_groups.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  test('consolidation and balance transfer mean borrowing more', () {
    expect(
      {
        for (final id in StrategyId.values)
          if (isBorrowingAlternative(id)) id,
      },
      {StrategyId.consolidation, StrategyId.balanceTransfer},
    );
  });

  test('the best pay-off method skips borrowing alternatives', () {
    PayoffResult feasible(StrategyId id) => PayoffResult.feasible(
      strategyId: id,
      plan: const PayoffPlan(
        debts: [],
        months: [],
        totalPaid: Money(1, 'GBP'),
        totalInterest: Money.zero('GBP'),
        totalFees: Money.zero('GBP'),
      ),
    );
    final ranked = [
      feasible(StrategyId.consolidation),
      const PayoffResult.neverClears(strategyId: StrategyId.snowball),
      feasible(StrategyId.avalanche),
    ];
    expect(bestPayOffMethod(ranked)?.strategyId, StrategyId.avalanche);
    expect(bestPayOffMethod([feasible(StrategyId.balanceTransfer)]), isNull);
  });
}
