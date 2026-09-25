import 'package:debt_destroyer/features/progress/domain/progress.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Check-ins and starting points, stored beside the debts.
abstract interface class ProgressHistoryReader {
  /// Everything recorded, re-emitted after every change, in [currencyCode].
  Stream<ProgressHistory> watch(String currencyCode);

  Future<ProgressHistory> load(String currencyCode);
}

abstract interface class ProgressRepository implements ProgressHistoryReader {
  /// Records a check-in of [balances] (debt id → balance) at [at] and, in the
  /// same transaction, sets each debt's balance; a zero clears that debt
  /// (clearedAt = [at]). Names are read from the debts.
  Future<CheckIn> saveCheckIn({
    required DateTime at,
    required Map<String, Money> balances,
  });

  /// Records a starting point: a start check-in of the current [balances]
  /// (debts unchanged) and the start itself.
  Future<StartingPoint> recordStart({
    required DateTime at,
    required Map<String, Money> balances,
    required StrategyId strategy,
    required StartReason reason,
    required List<int> projectedTotals,
    String? debtName,
  });

  /// "Start fresh": deletes every check-in and starting point. Debts, when
  /// they were cleared and the settings are untouched.
  Future<void> clearHistory();
}
