import 'package:collection/collection.dart';
import 'package:payoff_engine/src/allocation_order.dart';
import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/interest.dart';
import 'package:payoff_engine/src/minimum_payment.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/payoff_result.dart';
import 'package:payoff_engine/src/strategy.dart';

/// A balance above this (in minor units) means the debt is growing without
/// bound; it also keeps `balance * aprBps` well inside 64-bit integers.
const int kBalanceCeilingMinor = 10000000000000;

/// Pays off [debts] (not empty) month by month with [budget]. Each month:
/// add interest at each debt's rate for that month, pay every minimum, then
/// spend what is left on overpayable debts in [order] (unless [allowExtra]
/// is false). The plan lists debts in the order they are cleared. [fees] are
/// reported as the plan's fees; they are already in the balances.
///
/// [debts] is assumed already validated, non-empty and in a single
/// currency; callers normally reach this through `calculate` rather than
/// calling it directly.
///
/// [groups] lists the portions of each card as indexes into [debts], the
/// card's own debt first. A card's minimum is worked out once on its total
/// with its own debt's rule and paid to its portions lowest current rate
/// first; money above the minimum goes to its portions highest current rate
/// first (the UK rule). Cards are ranked for extra money by their
/// best-ranked portion in [order]. Without [groups] every debt is a card of
/// its own.
PayoffResult simulate({
  required StrategyId strategyId,
  required List<Debt> debts,
  required Money budget,
  required Money fees,
  required AllocationOrder order,
  bool allowExtra = true,
  PlanChange? change,
  List<List<int>>? groups,
}) {
  final currency = budget.currency;
  final n = debts.length;
  final balances = [for (final d in debts) d.balance.minor];
  final clearedAt = List<(int, int)?>.filled(n, null);
  final rows = <_Month>[];
  final cards =
      groups ??
      [
        for (var i = 0; i < n; i++) [i],
      ];
  final cardOf = List.filled(n, 0);
  for (final (c, members) in cards.indexed) {
    for (final i in members) {
      cardOf[i] = c;
    }
  }
  // A card's portions by the rate charged in [month]; ties keep list order.
  // Every debt is its own single-member card without a move (the common
  // case), so this is the inner loop of every strategy: skip the copy and
  // sort when there's nothing to order.
  List<int> byRate(List<int> members, int month, {required bool highestFirst}) {
    if (members.length == 1) return members;
    final sorted = [...members];
    mergeSort<int>(
      sorted,
      compare: (a, b) {
        final byApr = aprInMonth(
          debts[a],
          month,
        ).compareTo(aprInMonth(debts[b], month));
        return highestFirst ? -byApr : byApr;
      },
    );
    return sorted;
  }

  final interestOn = monthlyInterest();
  var month = 0;
  while (balances.any((b) => b > 0)) {
    if (month == kMaxMonths) {
      return PayoffResult.neverClears(strategyId: strategyId);
    }
    month++;

    final interest = List.filled(n, 0);
    for (var i = 0; i < n; i++) {
      if (balances[i] <= 0) continue;
      interest[i] = interestOn(balances[i], aprInMonth(debts[i], month));
      balances[i] += interest[i];
      if (balances[i] > kBalanceCeilingMinor) {
        return PayoffResult.neverClears(strategyId: strategyId);
      }
    }

    final payments = List.filled(n, 0);
    var minimumsTotal = 0;
    for (final members in cards) {
      final total = members.fold(0, (s, i) => s + balances[i]);
      if (total <= 0) continue;
      var due = minimumPaymentMinor(debts[members.first], total);
      minimumsTotal += due;
      for (final i in byRate(members, month, highestFirst: false)) {
        if (due == 0) break;
        final pay = due < balances[i] ? due : balances[i];
        payments[i] += pay;
        due -= pay;
      }
    }
    if (minimumsTotal > budget.minor) {
      return PayoffResult.infeasible(
        strategyId: strategyId,
        shortfall: Money(minimumsTotal - budget.minor, currency),
        month: month,
      );
    }

    for (var i = 0; i < n; i++) {
      balances[i] -= payments[i];
    }
    // Cards in the order their best-ranked portion appears; within a card,
    // highest current rate first.
    final seen = <int>{};
    final sequence = [
      for (final i in order(month))
        if (seen.add(cardOf[i]))
          ...byRate(cards[cardOf[i]], month, highestFirst: true),
    ];
    if (allowExtra) {
      var remaining = budget.minor - minimumsTotal;
      for (final i in sequence) {
        if (remaining == 0) break;
        final overpayable = debts[cards[cardOf[i]].first].allowsOverpayment;
        if (!overpayable || balances[i] == 0) continue;
        final extra = remaining < balances[i] ? remaining : balances[i];
        payments[i] += extra;
        balances[i] -= extra;
        remaining -= extra;
      }
    }
    for (final (position, i) in sequence.indexed) {
      if (balances[i] == 0 && clearedAt[i] == null) {
        clearedAt[i] = (month, position);
      }
    }
    rows.add((interest: interest, payments: payments, closing: [...balances]));
  }

  // Columns in clearing order; debts cleared in the same month keep that
  // month's allocation order.
  final columns = [for (var i = 0; i < n; i++) i]
    ..sort((a, b) {
      final (monthA, positionA) = clearedAt[a]!;
      final (monthB, positionB) = clearedAt[b]!;
      final byMonth = monthA.compareTo(monthB);
      return byMonth != 0 ? byMonth : positionA.compareTo(positionB);
    });
  List<Money> pick(List<int> values) => [
    for (final i in columns) Money(values[i], currency),
  ];
  int total(List<int> Function(_Month) column) =>
      rows.fold(0, (sum, row) => column(row).fold(sum, (s, v) => s + v));

  return PayoffResult.feasible(
    strategyId: strategyId,
    plan: PayoffPlan(
      debts: [
        for (final i in columns)
          PlanDebt(
            id: debts[i].id,
            name: debts[i].name,
            startingBalance: debts[i].balance,
          ),
      ],
      months: [
        for (final (k, row) in rows.indexed)
          MonthRow(
            month: k + 1,
            interest: pick(row.interest),
            payments: pick(row.payments),
            closingBalances: pick(row.closing),
          ),
      ],
      totalPaid: Money(total((r) => r.payments), currency),
      totalInterest: Money(total((r) => r.interest), currency),
      totalFees: fees,
      change: change,
    ),
  );
}

typedef _Month = ({List<int> interest, List<int> payments, List<int> closing});
