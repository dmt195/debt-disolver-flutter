import 'package:debt_destroyer/features/analysis/domain/plan_series.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

Money gbp(int minor) => Money(minor, 'GBP');

MonthRow row(int month, List<int> pay, List<int> close) => MonthRow(
  month: month,
  interest: [for (final _ in pay) gbp(0)],
  payments: [for (final p in pay) gbp(p)],
  closingBalances: [for (final c in close) gbp(c)],
);

String name(PlanDebt d) => d.name;

void main() {
  // Overdraft clears in month 2; Visa (with a portion moved from Store)
  // clears in month 3.
  final plan = PayoffPlan(
    debts: [
      PlanDebt(id: 'od', name: 'Overdraft', startingBalance: gbp(20000)),
      PlanDebt(id: 'visa', name: 'Visa', startingBalance: gbp(30000)),
      PlanDebt(
        id: 'visa#from-store',
        name: 'Store',
        startingBalance: gbp(10000),
      ),
    ],
    months: [
      row(1, [12000, 5000, 3000], [8000, 25000, 7000]),
      row(2, [8000, 9000, 3000], [0, 16000, 4000]),
      row(3, [0, 16000, 4000], [0, 0, 0]),
    ],
    totalPaid: gbp(60000),
    totalInterest: gbp(0),
    totalFees: gbp(0),
  );

  test('total owed starts with the starting balances', () {
    expect(totalOwedSeries(plan), [600.0, 400.0, 200.0, 0.0]);
  });

  test('an empty plan still gives two points', () {
    final done = plan.copyWith(months: []);
    expect(totalOwedSeries(done), [600.0, 600.0]);
  });

  test('portions are merged into their card', () {
    final groups = groupPlanDebts(plan, name);
    expect([for (final g in groups) g.id], ['od', 'visa']);
    expect(groups[1].name, 'Visa');
    expect(groups[1].columns, [1, 2]);
  });

  test('milestones say when each debt clears and what rolls on', () {
    final m = milestones(plan, name);
    expect(m, hasLength(2));
    expect(m[0].debt.name, 'Overdraft');
    expect(m[0].month, 2);
    expect(m[0].rollsOn, gbp(12000)); // month 1, the month before its last
    expect(m[0].next!.id, 'visa');
    expect(m[1].month, 3);
    expect(m[1].next, isNull);
  });

  test('first month payments are grouped and positive only', () {
    final p = firstMonthPayments(plan, name);
    expect(
      [for (final x in p) (x.debt.id, x.amount.minor)],
      [('od', 12000), ('visa', 8000)],
    );
  });

  test('money split separates interest and fees', () {
    final withCosts = plan.copyWith(
      totalPaid: gbp(70000),
      totalInterest: gbp(8000),
      totalFees: gbp(2000),
    );
    final s = moneySplit(withCosts);
    expect(s.principal, gbp(60000));
    expect(s.interest, gbp(8000));
    expect(s.fees, gbp(2000));
  });

  test('payoff position counts groups, not columns', () {
    expect(payoffPosition(plan, 'od'), 1);
    expect(payoffPosition(plan, 'visa'), 2);
    expect(payoffPosition(plan, 'store'), isNull);
  });

  test('APR heat bands', () {
    expect(aprHeat(3990), AprHeat.high);
    expect(aprHeat(2000), AprHeat.high);
    expect(aprHeat(1999), AprHeat.medium);
    expect(aprHeat(1000), AprHeat.medium);
    expect(aprHeat(790), AprHeat.low);
  });
}
