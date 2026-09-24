import 'package:payoff_engine/src/debt.dart';

/// Highest rate charged in [month] first (a promotional rate counts while it
/// lasts); ties broken by name, then id.
int compareHighestAprInMonth(Debt a, Debt b, int month) {
  final byApr = aprInMonth(b, month).compareTo(aprInMonth(a, month));
  return byApr != 0 ? byApr : _byNameThenId(a, b);
}

/// Smallest balance first; ties broken by name, then id.
int compareSmallestBalanceFirst(Debt a, Debt b) {
  final byBalance = a.balance.compareTo(b.balance);
  return byBalance != 0 ? byBalance : _byNameThenId(a, b);
}

int _byNameThenId(Debt a, Debt b) {
  final byName = a.name.compareTo(b.name);
  return byName != 0 ? byName : a.id.compareTo(b.id);
}
