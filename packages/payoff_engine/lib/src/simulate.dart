import 'package:payoff_engine/src/allocation_order.dart';
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
/// spend what is left on overpayable debts in [order] (unless [allowExtra]
/// is false). The plan lists debts in the order they are cleared. [fees] are
/// reported as the plan's fees; they are already in the balances.
///
/// [debts] is assumed already validated, non-empty and in a single
/// currency; callers normally reach this through `calculate` rather than
/// calling it directly.
PayoffResult simulate({
  required StrategyId strategyId,
  required List<Debt> debts,
  required Money budget,
  required Money fees,
  required AllocationOrder order,
  bool allowExtra = true,
  PlanChange? change,
}) {
  final currency = budget.currency;
  final n = debts.length;
  final balances = [for (final d in debts) d.balance.minor];
  final clearedAt = List<(int, int)?>.filled(n, null);
  final rows = <_Month>[];
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

    for (var i = 0; i < n; i++) {
      balances[i] -= payments[i];
    }
    final priority = order(month);
    if (allowExtra) {
      var remaining = budget.minor - minimumsTotal;
      for (final i in priority) {
        if (remaining == 0) break;
        if (!debts[i].allowsOverpayment || balances[i] == 0) continue;
        final extra = remaining < balances[i] ? remaining : balances[i];
        payments[i] += extra;
        balances[i] -= extra;
        remaining -= extra;
      }
    }
    for (final (position, i) in priority.indexed) {
      if (balances[i] == 0 && clearedAt[i] == null) {
        clearedAt[i] = (month, position);
      }
    }
    rows.add((interest: interest, payments: payments, closing: [...balances]));
  }

  // Columns in clearing order; debts cleared in the same month keep that
  // month's allocation order.
  final columns = [for (var i = 0; i < n; i++) i]
    ..sort((a, b) {
      final (monthA, positionA) = clearedAt[a]!;
      final (monthB, positionB) = clearedAt[b]!;
      final byMonth = monthA.compareTo(monthB);
      return byMonth != 0 ? byMonth : positionA.compareTo(positionB);
    });
  List<Money> pick(List<int> values) => [
    for (final i in columns) Money(values[i], currency),
  ];
  int total(List<int> Function(_Month) column) =>
      rows.fold(0, (sum, row) => column(row).fold(sum, (s, v) => s + v));

  return PayoffResult.feasible(
    strategyId: strategyId,
    plan: PayoffPlan(
      debts: [
        for (final i in columns)
          PlanDebt(
            id: debts[i].id,
            name: debts[i].name,
            startingBalance: debts[i].balance,
          ),
      ],
      months: [
        for (final (k, row) in rows.indexed)
          MonthRow(
            month: k + 1,
            interest: pick(row.interest),
            payments: pick(row.payments),
            closingBalances: pick(row.closing),
          ),
      ],
      totalPaid: Money(total((r) => r.payments), currency),
      totalInterest: Money(total((r) => r.interest), currency),
      totalFees: fees,
      change: change,
    ),
  );
}

typedef _Month = ({List<int> interest, List<int> payments, List<int> closing});
