import 'package:flutter/foundation.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Why a starting point was recorded (spec §6.3).
enum StartReason { initial, debtAdded, debtDeleted, planSwitched, restarted }

/// A dated record of balances: one the user entered, or one taken at a
/// starting point ([isStart]).
@immutable
class CheckIn {
  const CheckIn({
    required this.id,
    required this.at,
    required this.isStart,
    required this.total,
    required this.balances,
  });

  final String id;
  final DateTime at;
  final bool isStart;
  final Money total;

  /// Debt id → (name at the time, balance). A zero marks a debt cleared here.
  final Map<String, ({String name, Money balance})> balances;
}

/// Where progress is measured from: the followed plan's projection as it
/// stood at [at] (spec §6.3).
@immutable
class StartingPoint {
  const StartingPoint({
    required this.id,
    required this.at,
    required this.checkInId,
    required this.strategy,
    required this.reason,
    required this.projectedTotals,
    this.debtName,
  });

  final String id;
  final DateTime at;

  /// The start check-in holding the balances it started from.
  final String checkInId;
  final StrategyId strategy;
  final StartReason reason;

  /// The debt added or deleted, for labelling the restart.
  final String? debtName;

  /// Total owed at month 0 (the start) and after each month, minor units.
  final List<int> projectedTotals;
}

/// Everything recorded, oldest first.
@immutable
class ProgressHistory {
  const ProgressHistory({this.checkIns = const [], this.starts = const []});

  final List<CheckIn> checkIns;
  final List<StartingPoint> starts;

  StartingPoint? get firstStart => starts.firstOrNull;
  StartingPoint? get latestStart => starts.lastOrNull;
  CheckIn? get lastCheckIn => checkIns.lastOrNull;

  CheckIn checkInFor(StartingPoint start) =>
      checkIns.firstWhere((c) => c.id == start.checkInId);
}
