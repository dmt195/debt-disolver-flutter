import 'package:payoff_engine/payoff_engine.dart';

/// Orders results for display: feasible plans cheapest first (ties: fewer
/// months, then strategy order), then infeasible, then never-clearing, and
/// finally not-applicable ones.
List<PayoffResult> rankResults(List<PayoffResult> results) {
  int group(PayoffResult r) => switch (r) {
    Feasible() => 0,
    Infeasible() => 1,
    NeverClears() => 2,
    NotApplicable() => 3,
  };
  int compare(PayoffResult a, PayoffResult b) {
    final byGroup = group(a).compareTo(group(b));
    if (byGroup != 0) return byGroup;
    if (a is Feasible && b is Feasible) {
      final byCost = a.plan.totalPaid.compareTo(b.plan.totalPaid);
      if (byCost != 0) return byCost;
      final byMonths = a.plan.monthsToClear.compareTo(b.plan.monthsToClear);
      if (byMonths != 0) return byMonths;
    }
    return a.strategyId.index.compareTo(b.strategyId.index);
  }

  return [...results]..sort(compare);
}
