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

/// The balance for which [payment] is the monthly payment at [aprBps] over
/// [months] months.
///
/// Many balances round to the same whole-penny payment. Among those, this is
/// the roundest: a multiple of 100,000, 10,000, 1,000 or 100 minor units
/// (£1,000, £100, £10, £1), then the middle of the range. So the payment for
/// a £5,000.00 loan reads back as £5,000.00, not £5,000.31. The payment
/// always clears the balance it returns within [months].
LoanResult loanBalance({
  required int aprBps,
  required Money payment,
  required int months,
}) {
  if (!_amountOk(payment.minor) || !_aprOk(aprBps) || !_monthsOk(months)) {
    return _outOfRange;
  }
  final interestOn = monthlyInterest();
  bool clears(int balance, int pay) =>
      _run(balance, aprBps, pay, months, interestOn) != null;
  // Interest is never negative, so no more than payment × months; anything
  // past the largest valid amount is out of range anyway.
  final ceiling = payment.minor * months;
  var low = 0;
  var high = ceiling < kMaxAmountMinor + 1 ? ceiling : kMaxAmountMinor + 1;
  while (low < high) {
    final mid = low + (high - low + 1) ~/ 2;
    if (clears(mid, payment.minor)) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  final largest = low;
  // The smallest balance a penny less no longer clears: from there up to
  // [largest], this payment is exactly the one needed.
  final less = payment.minor - 1;
  var smallest = 1;
  if (less > 0) {
    low = 0;
    high = largest + 1;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (clears(mid, less)) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    smallest = low;
  }
  final chosen = smallest > largest
      ? largest
      : _roundestAmount(smallest, largest);
  if (!_amountOk(chosen)) return _outOfRange;
  return _solved(
    Money(chosen, payment.currency),
    aprBps,
    payment.minor,
    _run(chosen, aprBps, payment.minor, months, interestOn)!,
  );
}

/// The roundest amount in [low]..[high]: a multiple of 100,000, 10,000,
/// 1,000 or 100 minor units, else the middle.
int _roundestAmount(int low, int high) {
  for (final step in const [100000, 10000, 1000, 100]) {
    final candidate = (low + step - 1) ~/ step * step;
    if (candidate <= high) return candidate;
  }
  return low + (high - low) ~/ 2;
}

/// The APR, in basis points, that makes [payment] the monthly payment for
/// [balance] over [months] months (spec §2.4).
///
/// Many APRs round to the same whole-penny payment. Among those, this is the
/// roundest: a whole percent, then a tenth of one, then the middle of the
/// range. So a real 0% loan reads as 0%, and a loan worked out at 19.9% reads
/// back as 19.9%. Any APR it returns still clears the loan within [months].
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
  bool clears(int pay, int aprBps) =>
      _run(balance.minor, aprBps, pay, months, interestOn) != null;
  if (!clears(payment.minor, 0)) {
    return const LoanImpossible(LoanProblem.rateBelowZero);
  }
  // Searched past 100%, so a loan at exactly 100% can be told apart from one
  // above it.
  const cap = 20000;
  // The highest APR at which the payment still clears.
  var low = 0;
  var high = cap;
  while (low < high) {
    final mid = low + (high - low + 1) ~/ 2;
    if (clears(payment.minor, mid)) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  final highest = low;
  // The lowest APR at which a penny less no longer clears: from there up to
  // [highest], this payment is exactly the one needed.
  final less = payment.minor - 1;
  var lowest = 0;
  if (less > 0 && clears(less, 0)) {
    low = 0;
    high = cap + 1;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (clears(less, mid)) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    lowest = low;
  }
  if (lowest > 10000) return const LoanImpossible(LoanProblem.rateTooHigh);
  final top = highest < 10000 ? highest : 10000;
  // More than enough even at the highest rate: no range to choose from.
  final aprBps = lowest > top ? top : _roundest(lowest, top);
  return _solved(
    balance,
    aprBps,
    payment.minor,
    _run(balance.minor, aprBps, payment.minor, months, interestOn)!,
  );
}

/// The roundest APR in [low]..[high]: a multiple of 100 bps, then of 10,
/// else the middle.
int _roundest(int low, int high) {
  for (final step in const [100, 10]) {
    final candidate = (low + step - 1) ~/ step * step;
    if (candidate <= high) return candidate;
  }
  return low + (high - low) ~/ 2;
}
