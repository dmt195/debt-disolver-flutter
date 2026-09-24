import 'package:payoff_engine/payoff_engine.dart';

/// What a plan saves compared with paying only the minimums.
typedef Savings = ({Money money, int months});

/// [plan]'s savings against [baseline], or null when the baseline doesn't
/// clear the debts or [plan] costs no less. Months never go below zero.
Savings? savingsAgainst(PayoffPlan plan, PayoffResult baseline) {
  if (baseline is! Feasible) return null;
  final money = baseline.plan.totalPaid - plan.totalPaid;
  if (!money.isPositive) return null;
  final months = baseline.plan.monthsToClear - plan.monthsToClear;
  return (money: money, months: months > 0 ? months : 0);
}
