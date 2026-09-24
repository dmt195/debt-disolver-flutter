import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/rounding.dart';

/// The payment [debt] requires this month at its current balance: the larger
/// of its floor and its percentage, but never more than the balance. The
/// calculator applies the same rule after adding each month's interest.
Money minimumPayment(Debt debt) {
  final balance = debt.balance.minor;
  if (balance <= 0) return Money.zero(debt.balance.currency);
  final byPercent = divideHalfEven(balance * debt.minPaymentPercentBps, 10000);
  final floor = debt.minPaymentFloor.minor;
  final minimum = byPercent > floor ? byPercent : floor;
  return Money(minimum < balance ? minimum : balance, debt.balance.currency);
}

/// The sum of [minimumPayment] over [debts], in [currency].
Money totalMinimumPayments(List<Debt> debts, {required String currency}) =>
    debts.fold(Money.zero(currency), (sum, d) => sum + minimumPayment(d));
