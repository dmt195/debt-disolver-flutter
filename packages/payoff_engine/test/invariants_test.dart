// Randomised checks of properties every plan must satisfy.
import 'dart:math';

import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const cases = 300;

  List<Debt> randomDebts(Random r) => [
    for (var i = 0; i < 1 + r.nextInt(5); i++)
      debt(
        id: 'd$i',
        type: DebtType.values[r.nextInt(DebtType.values.length)],
        balance: 1 + r.nextInt(1000000),
        aprBps: r.nextInt(3001),
        minPaymentPercentBps: r.nextInt(501),
        minPaymentFloor: r.nextInt(5001),
        allowsOverpayment: r.nextInt(4) != 0,
        promo: r.nextInt(3) == 0
            ? Promo(aprBps: r.nextInt(501), months: 1 + r.nextInt(24))
            : null,
      ),
  ];

  StrategyParameters randomParameters(Random r) => StrategyParameters(
    consolidationAprBps: r.nextInt(2001),
    transferFeeBps: r.nextInt(501),
    promoMonths: r.nextInt(25),
    revertAprBps: r.nextInt(3001),
    transferCreditLimit: r.nextBool() ? null : gbp(1 + r.nextInt(2000000)),
  );

  Money sum(Iterable<Money> xs) => xs.fold(gbp(0), (a, b) => a + b);

  test('every result satisfies the plan invariants', () {
    final r = Random(42);
    var feasible = 0;
    for (var c = 0; c < cases; c++) {
      final debts = randomDebts(r);
      final budget = gbp(1 + r.nextInt(200000));
      final strategies = [
        ...standardStrategies(randomParameters(r)),
        const Strategy.minimumsOnly(),
      ];
      for (final s in strategies) {
        final result = calculate(
          debts: debts,
          monthlyBudget: budget,
          strategy: s,
        );
        final label = 'case $c, ${s.id}';
        switch (result) {
          case Infeasible(:final shortfall, :final month):
            expect(shortfall.isPositive, isTrue, reason: label);
            expect(month, inInclusiveRange(1, kMaxMonths), reason: label);
          case NeverClears():
            break;
          case NotApplicable():
            break;
          case Feasible(:final plan):
            feasible++;
            final starting = sum(plan.debts.map((d) => d.startingBalance));
            expect(
              starting,
              sum(debts.map((d) => d.balance)) + plan.totalFees,
              reason: label,
            );
            expect(
              plan.totalPaid,
              starting + plan.totalInterest,
              reason: label,
            );
            expect(
              plan.payoffOrder.toSet(),
              hasLength(plan.debts.length),
              reason: label,
            );
            for (final (i, row) in plan.months.indexed) {
              expect(row.month, i + 1, reason: label);
              expect(
                row.closingBalances.every((b) => !b.isNegative),
                isTrue,
                reason: label,
              );
              expect(
                row.payments.every((p) => !p.isNegative),
                isTrue,
                reason: label,
              );
              expect(sum(row.payments) <= budget, isTrue, reason: label);
            }
            expect(
              plan.months.last.closingBalances.every((b) => b.isZero),
              isTrue,
              reason: label,
            );
            if (plan.change case TransferChange(
              :final moved,
              :final fee,
              :final creditLimit,
            )) {
              expect(
                sum(moved.map((m) => m.amount)) + fee <= creditLimit,
                isTrue,
                reason: label,
              );
            }
        }
      }
    }
    // Guard against a generator that never exercises the feasible path.
    expect(feasible, greaterThan(cases));
  });
}
