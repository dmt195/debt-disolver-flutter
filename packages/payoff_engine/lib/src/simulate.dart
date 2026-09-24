import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/minimum_payment.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/payoff_result.dart';
import 'package:payoff_engine/src/rounding.dart';
import 'package:payoff_engine/src/strategy.dart';

/// A balance above this (in minor units) means the debt is growing without
/// bound; it also keeps `balance * aprBps` well inside 64-bit integers.
const int kBalanceCeilingMinor = 10000000000000;

/// Pays off [debts] (not empty) month by month with [budget]. Each month:
/// add interest at each debt's rate for that month, pay every minimum, then
/// spend what is left on overpayable debts in list order. [fees] are
/// reported as the plan's fees; they are already in the balances.
PayoffResult simulate({
  required StrategyId strategyId,
  required List<Debt> debts,
  required Money budget,
  required Money fees,
}) {
  final currency = budget.currency;
  final n = debts.length;
  final balances = [for (final d in debts) d.balance.minor];
  final rows = <MonthRow>[];
  var month = 0;
  while (balances.any((b) => b > 0)) {
    if (month == kMaxMonths) {
      return PayoffResult.neverClears(strategyId: strategyId);
    }
    month++;

    final interest = List.filled(n, 0);
    for (var i = 0; i < n; i++) {
      if (balances[i] <= 0) continue;
      interest[i] = divideHalfEven(
        balances[i] * aprInMonth(debts[i], month),
        120000,
      );
      balances[i] += interest[i];
      if (balances[i] > kBalanceCeilingMinor) {
        return PayoffResult.neverClears(strategyId: strategyId);
      }
    }

    final payments = [
      for (var i = 0; i < n; i++) minimumPaymentMinor(debts[i], balances[i]),
    ];
    final minimumsTotal = payments.fold(0, (a, b) => a + b);
    if (minimumsTotal > budget.minor) {
      return PayoffResult.infeasible(
        strategyId: strategyId,
        shortfall: Money(minimumsTotal - budget.minor, currency),
        month: month,
      );
    }

    var remaining = budget.minor - minimumsTotal;
    for (var i = 0; i < n; i++) {
      balances[i] -= payments[i];
      if (remaining > 0 && debts[i].allowsOverpayment && balances[i] > 0) {
        final extra = remaining < balances[i] ? remaining : balances[i];
        payments[i] += extra;
        balances[i] -= extra;
        remaining -= extra;
      }
    }

    rows.add(
      MonthRow(
        month: month,
        interest: [for (final v in interest) Money(v, currency)],
        payments: [for (final v in payments) Money(v, currency)],
        closingBalances: [for (final v in balances) Money(v, currency)],
      ),
    );
  }

  final zero = Money.zero(currency);
  Money sum(List<Money> Function(MonthRow) column) =>
      rows.fold(zero, (total, row) => column(row).fold(total, (t, m) => t + m));

  return PayoffResult.feasible(
    strategyId: strategyId,
    plan: PayoffPlan(
      debts: [
        for (final d in debts)
          PlanDebt(id: d.id, name: d.name, startingBalance: d.balance),
      ],
      months: rows,
      totalPaid: sum((r) => r.payments),
      totalInterest: sum((r) => r.interest),
      totalFees: fees,
    ),
  );
}
