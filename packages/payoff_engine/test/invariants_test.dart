// Randomised checks of properties every plan must satisfy.
import 'dart:math';

import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const cases = 300;
  final strategies = standardStrategies(const StrategyParameters());

  List<Debt> randomDebts(Random r) => [
    for (var i = 0; i < 1 + r.nextInt(5); i++)
      debt(
        id: 'd$i',
        balance: 1 + r.nextInt(1000000),
        aprBps: r.nextInt(3001),
        minPaymentPercentBps: r.nextInt(501),
        minPaymentFloor: r.nextInt(5001),
        allowsOverpayment: r.nextInt(4) != 0,
      ),
  ];

  Money sum(Iterable<Money> xs) => xs.fold(gbp(0), (a, b) => a + b);

  test('every result satisfies the plan invariants', () {
    final r = Random(42);
    var feasible = 0;
    for (var c = 0; c < cases; c++) {
      final debts = randomDebts(r);
      final budget = gbp(1 + r.nextInt(200000));
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
          case Feasible(:final plan):
            feasible++;
            final effectiveBudget = s is Boosted
                ? gbp(divideHalfEven(budget.minor * 110, 100))
                : budget;
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
              plan.monthsToClear,
              lessThanOrEqualTo(kMaxMonths),
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
              expect(
                sum(row.payments) <= effectiveBudget,
                isTrue,
                reason: label,
              );
            }
            expect(
              plan.months.last.closingBalances.every((b) => b.isZero),
              isTrue,
              reason: label,
            );
            final aprs = [
              for (final id in plan.payoffOrder)
                debts
                    .firstWhere((d) => d.id == id, orElse: () => debts.first)
                    .aprBps,
            ];
            if (s is Avalanche || s is Boosted) {
              for (var i = 1; i < aprs.length; i++) {
                expect(aprs[i - 1] >= aprs[i], isTrue, reason: label);
              }
            }
            if (s is LowestAprFirst) {
              for (var i = 1; i < aprs.length; i++) {
                expect(aprs[i - 1] <= aprs[i], isTrue, reason: label);
              }
            }
        }
      }
    }
    // Guard against a generator that never exercises the feasible path.
    expect(feasible, greaterThan(cases));
  });
}
