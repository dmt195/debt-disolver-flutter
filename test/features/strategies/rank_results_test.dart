import 'package:debt_destroyer/features/strategies/domain/rank_results.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  const gbp0 = Money.zero('GBP');

  PayoffResult feasible(StrategyId id, {required int paid, int months = 1}) =>
      PayoffResult.feasible(
        strategyId: id,
        plan: PayoffPlan(
          debts: const [],
          months: [
            for (var m = 1; m <= months; m++)
              MonthRow(
                month: m,
                interest: const [],
                payments: const [],
                closingBalances: const [],
              ),
          ],
          totalPaid: Money(paid, 'GBP'),
          totalInterest: gbp0,
          totalFees: gbp0,
        ),
      );

  test('puts feasible plans first, cheapest first', () {
    final ranked = rankResults([
      feasible(StrategyId.avalanche, paid: 500),
      const PayoffResult.neverClears(strategyId: StrategyId.snowball),
      feasible(StrategyId.consolidation, paid: 300),
      const PayoffResult.infeasible(
        strategyId: StrategyId.customOrder,
        shortfall: Money(1, 'GBP'),
        month: 1,
      ),
      feasible(StrategyId.balanceTransfer, paid: 400),
    ]);
    expect(ranked.map((r) => r.strategyId), [
      StrategyId.consolidation,
      StrategyId.balanceTransfer,
      StrategyId.avalanche,
      StrategyId.customOrder,
      StrategyId.snowball,
    ]);
  });

  test('breaks cost ties by fewer months, then strategy order', () {
    final ranked = rankResults([
      feasible(StrategyId.customOrder, paid: 100, months: 3),
      feasible(StrategyId.snowball, paid: 100, months: 2),
      feasible(StrategyId.avalanche, paid: 100, months: 3),
    ]);
    expect(ranked.map((r) => r.strategyId), [
      StrategyId.snowball,
      StrategyId.avalanche,
      StrategyId.customOrder,
    ]);
  });

  test('puts strategies that do not apply last', () {
    final ranked = rankResults([
      const PayoffResult.notApplicable(
        strategyId: StrategyId.balanceTransfer,
        reason: NotApplicableReason.noTransferableBalances,
      ),
      const PayoffResult.neverClears(strategyId: StrategyId.snowball),
      feasible(StrategyId.avalanche, paid: 1),
    ]);
    expect(ranked.map((r) => r.strategyId), [
      StrategyId.avalanche,
      StrategyId.snowball,
      StrategyId.balanceTransfer,
    ]);
  });

  test('does not modify its input', () {
    final input = [
      feasible(StrategyId.avalanche, paid: 2),
      feasible(StrategyId.customOrder, paid: 1),
    ];
    rankResults(input);
    expect(input.first.strategyId, StrategyId.avalanche);
  });
}
