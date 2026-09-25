import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/analysis/domain/plan_series.dart';
import 'package:debt_destroyer/features/debts/domain/cleared_debt.dart';
import 'package:debt_destroyer/features/progress/domain/progress.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Whole calendar months from [from]'s month to [to]'s month.
int monthIndex(DateTime from, DateTime to) =>
    (to.year - from.year) * 12 + to.month - from.month;

/// The plan's total owed at month 0 and after each month, minor units.
List<int> projectedTotals(PayoffPlan plan) => [
  plan.debts.fold<int>(0, (s, d) => s + d.startingBalance.minor),
  for (final m in plan.months)
    m.closingBalances.fold<int>(0, (s, b) => s + b.minor),
];

int _oneMajorUnit(String currency) {
  var s = 1;
  for (var i = 0; i < currencyDecimalDigits(currency); i++) {
    s *= 10;
  }
  return s;
}

/// Paid off since the first starting point (spec §6.4): for each debt that
/// still exists, its first recorded balance less what it owes now.
({Money amount, int percent, DateTime? since}) paidOff(
  ProgressHistory history,
  List<Debt> uncleared,
  List<ClearedDebt> cleared,
  String currency,
) {
  final current = <String, int>{
    for (final d in uncleared) d.id: d.balance.minor,
    for (final c in cleared) c.id: 0,
  };
  final first = <String, int>{};
  for (final c in history.checkIns) {
    for (final MapEntry(key: id, value: b) in c.balances.entries) {
      first.putIfAbsent(id, () => b.balance.minor);
    }
  }
  var paid = 0;
  var from = 0;
  for (final MapEntry(key: id, value: now) in current.entries) {
    final start = first[id];
    if (start == null) continue;
    paid += start - now;
    from += start;
  }
  final percent = paid <= 0 || from == 0
      ? 0
      : (paid * 100 ~/ from).clamp(0, 100);
  return (
    amount: Money(paid, currency),
    percent: percent,
    since: history.firstStart?.at,
  );
}

/// Where the latest check-in stands against the latest starting point.
sealed class AheadBehind {
  const AheadBehind();
}

/// No check-in since the latest starting point.
class NoProgressYet extends AheadBehind {
  const NoProgressYet();
}

class OnTrack extends AheadBehind {
  const OnTrack();
}

/// As low as the plan expected [months] later.
class AheadMonths extends AheadBehind {
  const AheadMonths(this.months);

  final int months;
}

class AheadMoney extends AheadBehind {
  const AheadMoney(this.amount);

  final Money amount;
}

class Behind extends AheadBehind {
  const Behind(this.amount);

  final Money amount;
}

/// At the latest check-in, against the latest starting point's projection
/// (spec §6.5). Within 1% (or one major unit) is on track.
AheadBehind aheadBehind(ProgressHistory history, String currency) {
  final start = history.latestStart;
  final last = history.lastCheckIn;
  if (start == null || last == null) return const NoProgressYet();
  // Check-ins are in the order they were made, so "since the start" means
  // after its own check-in in the list, even at the same moment.
  final startIndex = history.checkIns.indexWhere(
    (c) => c.id == start.checkInId,
  );
  if (history.checkIns.length - 1 <= startIndex) return const NoProgressYet();
  final totals = start.projectedTotals;
  final m = monthIndex(start.at, last.at);
  final expected = m < totals.length ? totals[m] : 0;
  final actual = last.total.minor;
  final diff = expected - actual;
  final tolerance = [
    expected ~/ 100,
    _oneMajorUnit(currency),
  ].reduce((a, b) => a > b ? a : b);
  if (diff.abs() <= tolerance) return const OnTrack();
  if (diff < 0) return Behind(Money(-diff, currency));
  var matched = m;
  for (var j = m + 1; j < totals.length; j++) {
    if (totals[j] >= actual) matched = j;
  }
  final months = matched - m;
  return months >= 1 ? AheadMonths(months) : AheadMoney(Money(diff, currency));
}

/// What the plan expects each debt to owe [months] after it started (0 = the
/// balances it started from). Portions count with their card; past the
/// plan's end everything is 0.
Map<String, Money> expectedBalances(
  PayoffPlan plan,
  int months,
  List<Debt> debts,
) {
  if (months <= 0) return {for (final d in debts) d.id: d.balance};
  final currency = plan.totalPaid.currency;
  if (months > plan.monthsToClear) {
    return {for (final d in debts) d.id: Money.zero(d.balance.currency)};
  }
  final row = plan.months[months - 1].closingBalances;
  final byGroup = {
    for (final g in groupPlanDebts(plan, (d) => d.name))
      g.id: g.columns.fold<int>(0, (s, c) => s + row[c].minor),
  };
  // A card whose balance the plan moves onto another card expects 0. A debt
  // the plan doesn't pay at all (replaced by a consolidation loan or a
  // transfer card) keeps its balance: never pre-fill it as paid off.
  bool movedOnward(String id) =>
      plan.debts.any((d) => d.id.endsWith('#from-$id'));
  return {
    for (final d in debts)
      d.id: switch (byGroup[d.id]) {
        final minor? => Money(minor, currency),
        null when movedOnward(d.id) => Money.zero(currency),
        null => d.balance,
      },
  };
}

/// The starting point due now, if any (spec §6.3): the first ever; a plan
/// switch; a debt added (or re-opened); a debt deleted. Clearing a debt is
/// progress, not a restart. Nothing is due while the plan is infeasible.
({StartReason reason, String? debtName})? nextStart({
  required ProgressHistory history,
  required List<Debt> uncleared,
  required List<ClearedDebt> cleared,
  required StrategyId followed,
  required bool feasible,
}) {
  if (!feasible) return null;
  final latest = history.latestStart;
  if (latest == null) return (reason: StartReason.initial, debtName: null);
  if (followed != latest.strategy) {
    return (reason: StartReason.planSwitched, debtName: null);
  }
  Money? latestMention(String id) {
    for (final c in history.checkIns.reversed) {
      if (c.balances[id] case final b?) return b.balance;
    }
    return null;
  }

  for (final d in uncleared) {
    final mention = latestMention(d.id);
    if (mention == null || mention.isZero) {
      return (reason: StartReason.debtAdded, debtName: d.name);
    }
  }
  final known = {
    for (final d in uncleared) d.id,
    for (final c in cleared) c.id,
  };
  // A deleted debt was still owing when last mentioned; one cleared since
  // the start and then tidied away is not a change of plan.
  for (final MapEntry(key: id, value: b)
      in history.checkInFor(latest).balances.entries) {
    if (!known.contains(id) && (latestMention(id)?.isPositive ?? false)) {
      return (reason: StartReason.debtDeleted, debtName: b.name);
    }
  }
  return null;
}

/// What the plan-vs-actual chart draws. x is months since the first
/// starting point; y is major units.
class ProgressChart {
  const ProgressChart({
    required this.actual,
    required this.current,
    required this.original,
    required this.markers,
    required this.today,
  });

  /// Every check-in's total.
  final List<(double, double)> actual;

  /// The latest starting point's projection, from its month.
  final List<(double, double)> current;

  /// The first starting point's projection, once there has been a restart.
  final List<(double, double)>? original;

  /// Every starting point after the first.
  final List<
    ({double x, StartReason reason, StrategyId strategy, String? debtName})
  >
  markers;

  /// Where today falls.
  final double today;
}

/// Chart data for [history] as of [now] (spec §6.7). Needs a starting point.
ProgressChart progressChartData(
  ProgressHistory history,
  DateTime now,
  String currency,
) {
  final first = history.firstStart!;
  final latest = history.latestStart!;
  final scale = _oneMajorUnit(currency);
  double x(DateTime at) {
    final days = DateTime(at.year, at.month + 1, 0).day;
    return monthIndex(first.at, at) + (at.day - 1) / days;
  }

  List<(double, double)> projection(StartingPoint s) {
    final x0 = monthIndex(first.at, s.at).toDouble();
    return [
      for (final (i, total) in s.projectedTotals.indexed)
        (x0 + i, total / scale),
    ];
  }

  return ProgressChart(
    actual: [
      for (final c in history.checkIns) (x(c.at), c.total.minor / scale),
    ],
    current: projection(latest),
    original: history.starts.length > 1 ? projection(first) : null,
    markers: [
      for (final s in history.starts.skip(1))
        (
          x: monthIndex(first.at, s.at).toDouble(),
          reason: s.reason,
          strategy: s.strategy,
          debtName: s.debtName,
        ),
    ],
    today: x(now),
  );
}
