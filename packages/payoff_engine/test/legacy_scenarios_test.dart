// Reference scenarios cross-checked against the legacy Android algorithm.
// Run `java legacy/reference/LegacySolver.java` from the repo root to
// reproduce the legacy figures quoted in the comments. Differences are
// either float rounding (a few pence) or deliberate bug fixes, noted inline.
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // LegacySolver uses the Java fallback settings (4% loan, 15-month promo).
  const params = StrategyParameters(consolidationAprBps: 400, promoMonths: 15);

  Map<StrategyId, PayoffResult> runAll(List<Debt> debts, int budget) => {
    for (final r in calculateAll(
      debts: debts,
      monthlyBudget: gbp(budget),
      parameters: params,
    ))
      r.strategyId: r,
  };

  void expectPlan(
    PayoffResult result, {
    required int months,
    required int paid,
    required int interest,
    int fees = 0,
    List<String>? order,
  }) {
    final plan = planOf(result);
    expect(plan.monthsToClear, months, reason: 'months');
    expect(plan.totalPaid, gbp(paid), reason: 'totalPaid');
    expect(plan.totalInterest, gbp(interest), reason: 'totalInterest');
    expect(plan.totalFees, gbp(fees), reason: 'totalFees');
    if (order != null) expect(plan.payoffOrder, order, reason: 'order');
  }

  test('S1: one interest-free card, 1000.00 at 250.00 a month', () {
    final p = runAll([debt(id: 'card', balance: 100000)], 25000);
    // Legacy: 4 months, 1000.00, for all three direct strategies.
    expectPlan(p[StrategyId.avalanche]!, months: 4, paid: 100000, interest: 0);
    // Legacy: 5 months, 1008.42 (interest 8.42).
    expectPlan(
      p[StrategyId.consolidation]!,
      months: 5,
      paid: 100842,
      interest: 842,
    );
    // Legacy moved the interest-free card anyway (5 months, 1040.00). v2
    // only moves balances that charge interest, so there is nothing to move.
    expect(
      p[StrategyId.balanceTransfer],
      const PayoffResult.notApplicable(
        strategyId: StrategyId.balanceTransfer,
        reason: NotApplicableReason.noTransferableBalances,
      ),
    );
  });

  test('S2: one 12% card, 1200.00, min 25.00 or 2%, at 100.00 a month', () {
    final p = runAll([
      debt(
        id: 'card',
        balance: 120000,
        aprBps: 1200,
        minPaymentPercentBps: 200,
        minPaymentFloor: 2500,
      ),
    ], 10000);
    // Legacy: 13 months, 1284.78.
    expectPlan(
      p[StrategyId.avalanche]!,
      months: 13,
      paid: 128478,
      interest: 8478,
    );
    // Legacy: 13 months, 1226.73.
    expectPlan(
      p[StrategyId.consolidation]!,
      months: 13,
      paid: 122673,
      interest: 2673,
    );
    // Legacy: 13 months, 1248.00 (fee reported as interest).
    expectPlan(
      p[StrategyId.balanceTransfer]!,
      months: 13,
      paid: 124800,
      interest: 0,
      fees: 4800,
    );
  });

  test('S3: two cards and a fixed-payment loan at 450.00 a month', () {
    final p = runAll([
      debt(
        id: 'c1',
        name: 'Card A',
        balance: 200000,
        aprBps: 1990,
        minPaymentPercentBps: 300,
        minPaymentFloor: 2500,
      ),
      debt(
        id: 'c2',
        name: 'Card B',
        balance: 150000,
        aprBps: 990,
        minPaymentPercentBps: 200,
        minPaymentFloor: 2500,
      ),
      debt(
        id: 'l1',
        name: 'Car loan',
        type: DebtType.loan,
        balance: 300000,
        aprBps: 650,
        minPaymentFloor: 15000,
        allowsOverpayment: false,
      ),
    ], 45000);
    // Legacy: 22 months, 6961.84 (float rounding: 3p lower).
    expectPlan(
      p[StrategyId.avalanche]!,
      months: 22,
      paid: 696187,
      interest: 46187,
      order: ['c1', 'c2', 'l1'],
    );
    // Legacy: 15 months, 6672.90 (1p lower).
    expectPlan(
      p[StrategyId.consolidation]!,
      months: 15,
      paid: 667291,
      interest: 17291,
    );
    // Legacy moved everything, loan included: 16 months, 6760.00. v2 moves
    // only the two cards (3,500.00 + 140.00 fee); the fixed-payment car loan
    // stays and sets the pace.
    expectPlan(
      p[StrategyId.balanceTransfer]!,
      months: 22,
      paid: 682395,
      interest: 18395,
      fees: 14000,
      order: [kBalanceTransferDebtId, 'l1'],
    );
    expectPlan(
      p[StrategyId.snowball]!,
      months: 22,
      paid: 705007,
      interest: 55007,
      order: ['c2', 'c1', 'l1'],
    );
    expectPlan(
      p[StrategyId.customOrder]!,
      months: 22,
      paid: 696187,
      interest: 46187,
      order: ['c1', 'c2', 'l1'],
    );
  });

  test('S4: APRs 0.5% apart are ordered correctly (legacy comparator bug)', () {
    final p = runAll([
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
    ], 30000);
    // Legacy paid Alpha (18.0%) first: 8 months, 2125.72. Beta first is
    // cheaper.
    expectPlan(
      p[StrategyId.avalanche]!,
      months: 8,
      paid: 212424,
      interest: 12424,
      order: ['y', 'x'],
    );
    // Legacy: 7 months, 2026.02 (1p lower).
    expectPlan(
      p[StrategyId.consolidation]!,
      months: 7,
      paid: 202603,
      interest: 2603,
    );
    expectPlan(
      p[StrategyId.balanceTransfer]!,
      months: 7,
      paid: 208000,
      interest: 0,
      fees: 8000,
    );
  });
}
