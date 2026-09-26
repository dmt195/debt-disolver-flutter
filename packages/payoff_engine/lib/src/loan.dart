import 'package:payoff_engine/src/interest.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/payoff_result.dart';
import 'package:payoff_engine/src/simulate.dart';
import 'package:payoff_engine/src/validation.dart';

/// Why a loan's figures can't be worked out.
enum LoanProblem {
  /// The payment doesn't even cover the first month's interest.
  neverClears,

  /// The payment would clear the loan even above 100% APR.
  rateTooHigh,

  /// The payments add up to less than the balance.
  rateBelowZero,

  /// A term outside 1–[kMaxMonths] months, an amount outside
  /// 0.01–[kMaxAmountMinor], an APR outside 0–100%, or a loan that takes
  /// longer than [kMaxMonths] months.
  outOfRange,
}

/// What a fixed-payment loan's figures work out to (spec §2.4).
sealed class LoanResult {
  const LoanResult();
}

final class LoanSolved extends LoanResult {
  const LoanSolved({
    required this.balance,
    required this.aprBps,
    required this.payment,
    required this.months,
    required this.balances,
    required this.totalPaid,
  });

  /// The amount borrowed, or owed now.
  final Money balance;
  final int aprBps;

  /// The regular monthly payment.
  final Money payment;

  /// The number of payments; the last may be smaller.
  final int months;

  /// The opening balance, then the balance after each payment: [months] + 1
  /// values, the last zero.
  final List<Money> balances;

  /// What is actually paid: the regular payments and a smaller last one.
  final Money totalPaid;

  /// The interest charged over the loan.
  Money get totalInterest => totalPaid - balance;
}

final class LoanImpossible extends LoanResult {
  const LoanImpossible(this.problem);

  final LoanProblem problem;
}

const _outOfRange = LoanImpossible(LoanProblem.outOfRange);

bool _amountOk(int minor) => minor > 0 && minor <= kMaxAmountMinor;

bool _monthsOk(int months) => months >= 1 && months <= kMaxMonths;

bool _aprOk(int aprBps) => aprBps >= 0 && aprBps <= 10000;

/// Pays [payment] a month off [balance] at [aprBps]: the opening balance
/// then the balance after each payment, and the total paid; or null if it
/// isn't clear within [maxMonths] or grows past [kBalanceCeilingMinor].
({List<int> balances, int paid})? _run(
  int balance,
  int aprBps,
  int payment,
  int maxMonths,
  MonthlyInterest interestOn,
) {
  final balances = [balance];
  var owed = balance;
  var paid = 0;
  while (owed > 0) {
    if (balances.length > maxMonths) return null;
    owed += interestOn(owed, aprBps);
    if (owed > kBalanceCeilingMinor) return null;
    final pay = payment < owed ? payment : owed;
    owed -= pay;
    paid += pay;
    balances.add(owed);
  }
  return (balances: balances, paid: paid);
}

LoanSolved _solved(
  Money balance,
  int aprBps,
  int payment,
  ({List<int> balances, int paid}) run,
) => LoanSolved(
  balance: balance,
  aprBps: aprBps,
  payment: Money(payment, balance.currency),
  months: run.balances.length - 1,
  balances: [for (final b in run.balances) Money(b, balance.currency)],
  totalPaid: Money(run.paid, balance.currency),
);

/// The smallest whole monthly payment that clears [balance] at [aprBps]
/// within [months] months, with the engine's own monthly interest and
/// rounding. Integer arithmetic throughout: a binary search.
LoanResult loanPayment({
  required Money balance,
  required int aprBps,
  required int months,
}) {
  if (!_amountOk(balance.minor) || !_aprOk(aprBps) || !_monthsOk(months)) {
    return _outOfRange;
  }
  final interestOn = monthlyInterest();
  final owed = balance.minor;
  final payment = smallestClearingPayment(owed, aprBps, months, interestOn);
  return _solved(
    balance,
    aprBps,
    payment,
    _run(owed, aprBps, payment, months, interestOn)!,
  );
}

/// The smallest whole payment that clears [owed] at [aprBps] within
/// [months] months: a binary search. No range checks, for the engine's own
/// use (`fixedLoanPayment` prices consolidation loans larger than any one
/// debt may be).
int smallestClearingPayment(
  int owed,
  int aprBps,
  int months,
  MonthlyInterest interestOn,
) {
  // Never less than an interest-free share; never more than clearing the
  // loan in its first month.
  var low = (owed + months - 1) ~/ months;
  var high = owed + interestOn(owed, aprBps);
  while (low < high) {
    final mid = low + (high - low) ~/ 2;
    if (_run(owed, aprBps, mid, months, interestOn) != null) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  return low;
}

/// How many payments of [payment] clear [balance] at [aprBps]; the last may
/// be smaller.
LoanResult loanMonths({
  required Money balance,
  required int aprBps,
  required Money payment,
}) {
  if (!_amountOk(balance.minor) ||
      !_amountOk(payment.minor) ||
      !_aprOk(aprBps)) {
    return _outOfRange;
  }
  final interestOn = monthlyInterest();
  if (payment.minor <= interestOn(balance.minor, aprBps)) {
    return const LoanImpossible(LoanProblem.neverClears);
  }
  final run = _run(
    balance.minor,
    aprBps,
    payment.minor,
    kMaxMonths,
    interestOn,
  );
  if (run == null) return _outOfRange;
  return _solved(balance, aprBps, payment.minor, run);
}

/// The largest balance that [payment] a month clears at [aprBps] within
/// [months] months.
LoanResult loanBalance({
  required int aprBps,
  required Money payment,
  required int months,
}) {
  if (!_amountOk(payment.minor) || !_aprOk(aprBps) || !_monthsOk(months)) {
    return _outOfRange;
  }
  final interestOn = monthlyInterest();
  bool clears(int balance) =>
      _run(balance, aprBps, payment.minor, months, interestOn) != null;
  // Interest is never negative, so no more than payment × months.
  var low = 0;
  var high = payment.minor * months;
  while (low < high) {
    final mid = low + (high - low + 1) ~/ 2;
    if (clears(mid)) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  if (!_amountOk(low)) return _outOfRange;
  final balance = Money(low, payment.currency);
  return _solved(
    balance,
    aprBps,
    payment.minor,
    _run(low, aprBps, payment.minor, months, interestOn)!,
  );
}

/// The highest APR, in basis points, at which [payment] a month clears
/// [balance] within [months] months.
LoanResult loanApr({
  required Money balance,
  required Money payment,
  required int months,
}) {
  if (!_amountOk(balance.minor) ||
      !_amountOk(payment.minor) ||
      !_monthsOk(months)) {
    return _outOfRange;
  }
  final interestOn = monthlyInterest();
  bool clearsAt(int aprBps) =>
      _run(balance.minor, aprBps, payment.minor, months, interestOn) != null;
  if (!clearsAt(0)) return const LoanImpossible(LoanProblem.rateBelowZero);
  if (clearsAt(10001)) return const LoanImpossible(LoanProblem.rateTooHigh);
  var low = 0;
  var high = 10000;
  while (low < high) {
    final mid = low + (high - low + 1) ~/ 2;
    if (clearsAt(mid)) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return _solved(
    balance,
    low,
    payment.minor,
    _run(balance.minor, low, payment.minor, months, interestOn)!,
  );
}
