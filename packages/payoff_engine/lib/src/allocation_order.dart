import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/debt_ordering.dart';
import 'package:payoff_engine/src/strategy.dart';

/// For a month (1-based), the order in which debts receive money above
/// their minimums, as indexes into the simulated list.
typedef AllocationOrder = List<int> Function(int month);

/// The order [strategy] pays [debts] in. Avalanche-style strategies re-rank
/// every month by the rate charged that month, so a debt on a 0% promo gets
/// only its minimum until the promo ends.
AllocationOrder allocationOrder(Strategy strategy, List<Debt> debts) {
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
    Avalanche() || Consolidation() || BalanceTransfer() || MinimumsOnly() =>
      (month) => sortedBy((a, b) => compareHighestAprInMonth(a, b, month)),
  };
}
