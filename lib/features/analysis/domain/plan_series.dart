import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/core/debt_colors.dart';
import 'package:payoff_engine/payoff_engine.dart';

int _scale(String currency) {
  var s = 1;
  for (var i = 0; i < currencyDecimalDigits(currency); i++) {
    s *= 10;
  }
  return s;
}

/// Total owed in major units: the starting total, then each month's closing
/// total. At least two points, so a chart can always draw a line.
List<double> totalOwedSeries(PayoffPlan plan) {
  final scale = _scale(plan.totalPaid.currency);
  final start =
      plan.debts.fold<int>(0, (s, d) => s + d.startingBalance.minor) / scale;
  final totals = [
    start,
    for (final m in plan.months)
      m.closingBalances.fold<int>(0, (s, b) => s + b.minor) / scale,
  ];
  return totals.length == 1 ? [start, start] : totals;
}

/// For month 0 (starting balances) through the last month, the cumulative
/// balance in major units: element `i` is the sum of debts `0..i`.
List<List<double>> stackedBalances(PayoffPlan plan) {
  final scale = _scale(plan.totalPaid.currency);
  List<double> cumulative(List<Money> balances) {
    var running = 0;
    return [for (final b in balances) (running += b.minor) / scale];
  }

  return [
    cumulative([for (final d in plan.debts) d.startingBalance]),
    for (final row in plan.months) cumulative(row.closingBalances),
  ];
}

/// A user's debt as it appears in a plan: its own column plus any portions
/// moved onto it (indexes into [PayoffPlan.debts]).
class PlanDebtGroup {
  const PlanDebtGroup(this.id, this.name, this.columns);

  final String id;
  final String name;
  final List<int> columns;
}

/// The plan's debts in clearing order, with each card-transfer portion
/// merged into its card.
List<PlanDebtGroup> groupPlanDebts(
  PayoffPlan plan,
  String Function(PlanDebt) nameOf,
) {
  final order = <String>[];
  final columns = <String, List<int>>{};
  final names = <String, String>{};
  for (final (i, d) in plan.debts.indexed) {
    final id = baseDebtId(d.id);
    if (!columns.containsKey(id)) {
      order.add(id);
      columns[id] = [];
    }
    columns[id]!.add(i);
    // The card's own column names the group; a portion only stands in until
    // the card's column is seen.
    if (id == d.id) names[id] = nameOf(d);
    names.putIfAbsent(id, () => nameOf(d));
  }
  return [for (final id in order) PlanDebtGroup(id, names[id]!, columns[id]!)];
}

Money _sum(List<Money> values, List<int> columns, String currency) =>
    Money(columns.fold<int>(0, (s, c) => s + values[c].minor), currency);

class Milestone {
  const Milestone(this.debt, this.month, this.rollsOn, this.next);

  final PlanDebtGroup debt;

  /// 1-based: the first month the debt's balance is zero.
  final int month;

  /// What was being paid on it in a full month, which rolls on to [next].
  final Money rollsOn;

  final PlanDebtGroup? next;
}

/// When each debt is cleared, in clearing order.
List<Milestone> milestones(PayoffPlan plan, String Function(PlanDebt) nameOf) {
  final currency = plan.totalPaid.currency;
  final groups = groupPlanDebts(plan, nameOf);
  final result = <Milestone>[];
  for (final (gi, g) in groups.indexed) {
    final idx = plan.months.indexWhere(
      (m) => _sum(m.closingBalances, g.columns, currency).isZero,
    );
    if (idx < 0) continue;
    final full = idx == 0 ? 0 : idx - 1;
    result.add(
      Milestone(
        g,
        idx + 1,
        _sum(plan.months[full].payments, g.columns, currency),
        gi + 1 < groups.length ? groups[gi + 1] : null,
      ),
    );
  }
  result.sort((a, b) => a.month.compareTo(b.month));
  return result;
}

({Money principal, Money interest, Money fees}) moneySplit(PayoffPlan plan) => (
  principal: plan.totalPaid - plan.totalInterest - plan.totalFees,
  interest: plan.totalInterest,
  fees: plan.totalFees,
);

/// This month's payment on each debt, grouped, in clearing order.
List<({PlanDebtGroup debt, Money amount})> firstMonthPayments(
  PayoffPlan plan,
  String Function(PlanDebt) nameOf,
) {
  if (plan.months.isEmpty) return const [];
  final currency = plan.totalPaid.currency;
  final first = plan.months.first;
  return [
    for (final g in groupPlanDebts(plan, nameOf))
      if (_sum(first.payments, g.columns, currency) case final amount
          when amount.isPositive)
        (debt: g, amount: amount),
  ];
}

/// Where the user's debt [debtId] comes in the clearing order (1 first).
int? payoffPosition(PayoffPlan plan, String debtId) {
  final groups = groupPlanDebts(plan, (d) => d.name);
  final i = groups.indexWhere((g) => g.id == debtId);
  return i < 0 ? null : i + 1;
}

enum AprHeat { high, medium, low }

/// High from 20%, medium from 10% (spec §4.3).
AprHeat aprHeat(int aprBps) => aprBps >= 2000
    ? AprHeat.high
    : aprBps >= 1000
    ? AprHeat.medium
    : AprHeat.low;

/// One month's balance for each user debt, from per-column balances (major
/// units): portions are added to their card, and cleared debts left out.
List<({PlanDebtGroup debt, double amount})> groupedBalances(
  List<PlanDebtGroup> groups,
  List<double> columnBalances,
) => [
  for (final g in groups)
    if (g.columns.fold<double>(0, (s, c) => s + columnBalances[c])
        case final amount when amount > 0.005)
      (debt: g, amount: amount),
];
