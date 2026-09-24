import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/payoff_result.dart';
import 'package:payoff_engine/src/restructure.dart';
import 'package:payoff_engine/src/rounding.dart';
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

  final budget = switch (strategy) {
    Boosted(:final budgetPercent) => Money(
      divideHalfEven(monthlyBudget.minor * budgetPercent, 100),
      currency,
    ),
    _ => monthlyBudget,
  };
  final restructured = restructure(debts, strategy, budget: budget);
  return simulate(
    strategyId: strategy.id,
    debts: restructured.debts,
    budget: budget,
    fees: restructured.fees,
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
