import 'package:debt_destroyer/features/strategies/domain/savings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  const gbp0 = Money.zero('GBP');

  PayoffPlan plan({required int paid, required int months}) => PayoffPlan(
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
  );

  PayoffResult baseline({required int paid, required int months}) =>
      PayoffResult.feasible(
        strategyId: StrategyId.minimumsOnly,
        plan: plan(paid: paid, months: months),
      );

  test('money and months saved against the baseline', () {
    expect(
      savingsAgainst(
        plan(paid: 1000, months: 4),
        baseline(paid: 1500, months: 60),
      ),
      (money: const Money(500, 'GBP'), months: 56),
    );
  });

  test('nothing when the plan costs the same or more', () {
    expect(
      savingsAgainst(
        plan(paid: 1500, months: 4),
        baseline(paid: 1500, months: 60),
      ),
      isNull,
    );
    expect(
      savingsAgainst(
        plan(paid: 1600, months: 4),
        baseline(paid: 1500, months: 60),
      ),
      isNull,
    );
  });

  test('never negative months', () {
    expect(
      savingsAgainst(
        plan(paid: 1000, months: 70),
        baseline(paid: 1500, months: 60),
      )?.months,
      0,
    );
  });

  test('nothing when the baseline does not clear', () {
    expect(
      savingsAgainst(
        plan(paid: 1000, months: 4),
        const PayoffResult.neverClears(strategyId: StrategyId.minimumsOnly),
      ),
      isNull,
    );
  });
}
