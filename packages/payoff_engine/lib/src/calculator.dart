import 'package:payoff_engine/src/allocation_order.dart';
import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/payoff_result.dart';
import 'package:payoff_engine/src/restructure.dart';
import 'package:payoff_engine/src/simulate.dart';
import 'package:payoff_engine/src/strategy.dart';
import 'package:payoff_engine/src/validation.dart';

/// Simulates paying off [debts] with [monthlyBudget] using [strategy].
/// Pure: [debts] is not modified.
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
  if (strategy case BalanceTransfer(
    creditLimit: final limit?,
  ) when limit.currency != currency) {
    throw ArgumentError.value(
      limit,
      'creditLimit',
      'not in the budget currency',
    );
  }
  if (strategy case Consolidation(:final termMonths) when termMonths < 1) {
    throw ArgumentError.value(termMonths, 'termMonths', 'must be at least 1');
  }
  final zero = Money.zero(currency);
  if (debts.isEmpty) {
    return PayoffResult.feasible(
      strategyId: strategy.id,
      plan: PayoffPlan(
        debts: const [],
        months: const [],
        totalPaid: zero,
        totalInterest: zero,
        totalFees: zero,
      ),
    );
  }

  return switch (restructure(debts, strategy)) {
    NotRestructurable(:final reason) => PayoffResult.notApplicable(
      strategyId: strategy.id,
      reason: reason,
    ),
    Restructured(debts: final paid, :final fees, :final change) => simulate(
      strategyId: strategy.id,
      debts: paid,
      budget: monthlyBudget,
      fees: fees,
      change: change,
      order: allocationOrder(strategy, paid),
      allowExtra: strategy is! MinimumsOnly,
    ),
  };
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

/// Paying only the minimums: the baseline [calculateAll]'s plans are
/// compared with.
PayoffResult calculateBaseline({
  required List<Debt> debts,
  required Money monthlyBudget,
}) => calculate(
  debts: debts,
  monthlyBudget: monthlyBudget,
  strategy: const Strategy.minimumsOnly(),
);
