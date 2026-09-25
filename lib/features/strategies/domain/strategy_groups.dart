import 'package:payoff_engine/payoff_engine.dart';

/// Strategies that mean taking on new credit. They are shown apart from the
/// ways to pay off, never as the cheapest or best plan: they only help if
/// the borrower stops adding to their debts, and may not be available with
/// a poor credit rating.
bool isBorrowingAlternative(StrategyId id) => switch (id) {
  StrategyId.consolidation || StrategyId.balanceTransfer => true,
  StrategyId.avalanche ||
  StrategyId.snowball ||
  StrategyId.customOrder ||
  StrategyId.minimumsOnly => false,
};

/// The first feasible pay-off method in [ranked] (already in display order;
/// see rankResults), or null if none clears the debts.
Feasible? bestPayOffMethod(List<PayoffResult> ranked) {
  for (final r in ranked) {
    if (r is Feasible && !isBorrowingAlternative(r.strategyId)) return r;
  }
  return null;
}
