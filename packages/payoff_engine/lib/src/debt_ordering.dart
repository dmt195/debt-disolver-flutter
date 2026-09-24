import 'package:payoff_engine/src/debt.dart';

/// Highest APR first; ties broken by name, then id.
int compareHighestAprFirst(Debt a, Debt b) {
  final byApr = b.aprBps.compareTo(a.aprBps);
  return byApr != 0 ? byApr : _byNameThenId(a, b);
}

/// Lowest APR first; ties broken by name, then id.
int compareLowestAprFirst(Debt a, Debt b) {
  final byApr = a.aprBps.compareTo(b.aprBps);
  return byApr != 0 ? byApr : _byNameThenId(a, b);
}

int _byNameThenId(Debt a, Debt b) {
  final byName = a.name.compareTo(b.name);
  return byName != 0 ? byName : a.id.compareTo(b.id);
}
