import 'package:payoff_engine/src/rounding.dart';
import 'package:payoff_engine/src/simulate.dart';

/// The smallest whole monthly payment that clears [balanceMinor] at
/// [aprBps] within [termMonths] months, using the calculator's own monthly
/// interest and rounding (so the loan really does clear on time). Integer
/// arithmetic throughout: a binary search, not an annuity formula.
int fixedLoanPayment({
  required int balanceMinor,
  required int aprBps,
  required int termMonths,
}) {
  bool clears(int payment) {
    var balance = balanceMinor;
    for (var m = 0; m < termMonths; m++) {
      balance += divideHalfEven(balance * aprBps, 120000);
      // A balance past the ceiling is growing without bound: this payment
      // cannot clear the loan, and it keeps `balance * aprBps` (used again
      // next month) well inside 64-bit integers.
      if (balance > kBalanceCeilingMinor) return false;
      balance -= payment < balance ? payment : balance;
      if (balance == 0) return true;
    }
    return false;
  }

  // Never less than an interest-free share; never more than clearing the
  // loan in its first month.
  var low = (balanceMinor + termMonths - 1) ~/ termMonths;
  var high = balanceMinor + divideHalfEven(balanceMinor * aprBps, 120000);
  while (low < high) {
    final mid = low + (high - low) ~/ 2;
    if (clears(mid)) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  return low;
}
