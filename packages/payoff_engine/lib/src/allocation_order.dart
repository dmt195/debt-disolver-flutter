import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/debt_ordering.dart';
import 'package:payoff_engine/src/strategy.dart';

/// For a month (1-based), the order in which debts receive money above
/// their minimums, as indexes into the simulated list.
typedef AllocationOrder = List<int> Function(int month);

/// The order [strategy] pays [debts] in.
///
/// Avalanche-style strategies re-rank every month. Given the month the plan
/// clears in ([horizon]), they rank by the interest a pound saves from that
/// month to the horizon ([compareMostInterestSaved]): a promo that ends soon
/// counts at its full rate afterwards, and one that outlasts the plan counts
/// as free. Without a horizon they rank by the rate charged that month.
AllocationOrder allocationOrder(
  Strategy strategy,
  List<Debt> debts, {
  int? horizon,
}) {
  final indexes = [for (var i = 0; i < debts.length; i++) i];
  List<int> sortedBy(int Function(Debt a, Debt b) compare) =>
      [...indexes]..sort((i, j) => compare(debts[i], debts[j]));
  AllocationOrder fixed(List<int> order) {
    final frozen = List<int>.unmodifiable(order);
    return (_) => frozen;
  }

  return switch (strategy) {
    Snowball() => fixed(sortedBy(compareSmallestBalanceFirst)),
    CustomOrder() => fixed(indexes),
    Avalanche() ||
    CardTransfers() ||
    Consolidation() ||
    BalanceTransfer() ||
    MinimumsOnly() => switch (horizon) {
      final h? => (month) => sortedBy(
        (a, b) => compareMostInterestSaved(a, b, month, h),
      ),
      null => (month) => sortedBy(
        (a, b) => compareHighestAprInMonth(a, b, month),
      ),
    },
  };
}
