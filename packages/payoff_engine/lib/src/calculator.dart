import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/debt_ordering.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/payoff_result.dart';
import 'package:payoff_engine/src/rounding.dart';
import 'package:payoff_engine/src/strategy.dart';
import 'package:payoff_engine/src/validation.dart';

const String kConsolidationDebtId = 'consolidation';
const String kBalanceTransferDebtId = 'balance-transfer';

/// A balance above this (in minor units) means the debt is growing without
/// bound; it also keeps `balance * aprBps` well inside 64-bit integers.
const int kBalanceCeilingMinor = 10000000000000;

/// Simulates paying off [debts] with [monthlyBudget] using [strategy].
///
/// Each month: add interest, pay every minimum, then spend what is left on
/// overpayable debts in priority order. Pure: [debts] is not modified.
///
/// Throws [ArgumentError] if any debt fails [validateDebt], the list fails
/// [validateDebtList], or [monthlyBudget] is negative.
PayoffResult calculate({
  required List<Debt> debts,
  required Money monthlyBudget,
  required Strategy strategy,
}) {
  if (monthlyBudget.isNegative) {
    throw ArgumentError.value(monthlyBudget, 'monthlyBudget', 'is negative');
  }
  if (validateDebtList(debts).isNotEmpty ||
      debts.any((d) => validateDebt(d).isNotEmpty)) {
    throw ArgumentError.value(debts, 'debts', 'contains invalid debts');
  }
  final currency = monthlyBudget.currency;
  final zero = Money.zero(currency);
  final originalTotal = debts.fold(zero, (sum, d) => sum + d.balance);

  final budget = switch (strategy) {
    Boosted(:final budgetPercent) => Money(
      divideHalfEven(monthlyBudget.minor * budgetPercent, 100),
      currency,
    ),
    _ => monthlyBudget,
  };

  final ordered = _debtsFor(strategy, debts, originalTotal, budget);
  final fees = ordered.fold(zero, (sum, d) => sum + d.balance) - originalTotal;
  final n = ordered.length;
  final balances = [for (final d in ordered) d.balance.minor];

  final rows = <MonthRow>[];
  var month = 0;
  while (balances.any((b) => b > 0)) {
    if (month == kMaxMonths) {
      return PayoffResult.neverClears(strategyId: strategy.id);
    }
    month++;

    final interest = List.filled(n, 0);
    for (var i = 0; i < n; i++) {
      if (balances[i] <= 0) continue;
      final apr = _aprFor(strategy, ordered[i], month);
      interest[i] = divideHalfEven(balances[i] * apr, 120000);
      balances[i] += interest[i];
      if (balances[i] > kBalanceCeilingMinor) {
        return PayoffResult.neverClears(strategyId: strategy.id);
      }
    }

    final payments = List.filled(n, 0);
    for (var i = 0; i < n; i++) {
      if (balances[i] <= 0) continue;
      final d = ordered[i];
      final byPercent = divideHalfEven(
        balances[i] * d.minPaymentPercentBps,
        10000,
      );
      final minimum = byPercent > d.minPaymentFloor.minor
          ? byPercent
          : d.minPaymentFloor.minor;
      payments[i] = minimum < balances[i] ? minimum : balances[i];
    }
    final minimumsTotal = payments.fold(0, (a, b) => a + b);
    if (minimumsTotal > budget.minor) {
      return PayoffResult.infeasible(
        strategyId: strategy.id,
        shortfall: Money(minimumsTotal - budget.minor, currency),
        month: month,
      );
    }

    var remaining = budget.minor - minimumsTotal;
    for (var i = 0; i < n; i++) {
      balances[i] -= payments[i];
      if (remaining > 0 && ordered[i].allowsOverpayment && balances[i] > 0) {
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

  Money sum(List<Money> Function(MonthRow) column) =>
      rows.fold(zero, (total, row) => column(row).fold(total, (t, m) => t + m));

  return PayoffResult.feasible(
    strategyId: strategy.id,
    plan: PayoffPlan(
      debts: [
        for (final d in ordered)
          PlanDebt(id: d.id, name: d.name, startingBalance: d.balance),
      ],
      months: rows,
      totalPaid: sum((r) => r.payments),
      totalInterest: sum((r) => r.interest),
      totalFees: fees,
    ),
  );
}

/// Runs every strategy in [standardStrategies], in that order.
List<PayoffResult> calculateAll({
  required List<Debt> debts,
  required Money monthlyBudget,
  required StrategyParameters parameters,
}) => [
  for (final strategy in standardStrategies(parameters))
    calculate(debts: debts, monthlyBudget: monthlyBudget, strategy: strategy),
];

List<Debt> _debtsFor(
  Strategy strategy,
  List<Debt> debts,
  Money total,
  Money budget,
) {
  if (total.isZero) return const [];
  return switch (strategy) {
    Avalanche() || Boosted() => [...debts]..sort(compareHighestAprFirst),
    LowestAprFirst() => [...debts]..sort(compareLowestAprFirst),
    Consolidation(:final aprBps) => [
      Debt(
        id: kConsolidationDebtId,
        name: 'Consolidation loan',
        type: DebtType.loan,
        balance: total,
        aprBps: aprBps,
        minPaymentPercentBps: 0,
        minPaymentFloor: budget,
        allowsOverpayment: false,
      ),
    ],
    BalanceTransfer(:final feeBps) => [
      Debt(
        id: kBalanceTransferDebtId,
        name: 'Balance transfer card',
        type: DebtType.creditCard,
        balance:
            total +
            Money(divideHalfEven(total.minor * feeBps, 10000), total.currency),
        aprBps: 0,
        minPaymentPercentBps: 0,
        minPaymentFloor: budget,
        allowsOverpayment: false,
      ),
    ],
  };
}

int _aprFor(Strategy strategy, Debt debt, int month) => switch (strategy) {
  BalanceTransfer(:final promoMonths, :final revertAprBps) =>
    month <= promoMonths ? 0 : revertAprBps,
  _ => aprInMonth(debt, month),
};
