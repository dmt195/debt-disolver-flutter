import 'package:debt_destroyer/core/currency.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// What the loan calculator works out (spec §4).
enum LoanUnknown { payment, amount, rate, term }

/// Works out [unknown] from the other three figures; null while any of them
/// is missing. The figure being worked out is ignored even if given.
/// [months] is the term.
LoanResult? solveLoan({
  required LoanUnknown unknown,
  Money? amount,
  int? aprBps,
  Money? payment,
  int? months,
}) => switch (unknown) {
  LoanUnknown.payment when amount != null && aprBps != null && months != null =>
    loanPayment(balance: amount, aprBps: aprBps, months: months),
  LoanUnknown.amount when aprBps != null && payment != null && months != null =>
    loanBalance(aprBps: aprBps, payment: payment, months: months),
  LoanUnknown.rate when amount != null && payment != null && months != null =>
    loanApr(balance: amount, payment: payment, months: months),
  LoanUnknown.term when amount != null && aprBps != null && payment != null =>
    loanMonths(balance: amount, aprBps: aprBps, payment: payment),
  _ => null,
};

/// The balance after each month, in major units, for the chart.
List<double> loanBalanceSeries(LoanSolved loan) {
  var scale = 1;
  for (var i = 0; i < currencyDecimalDigits(loan.balance.currency); i++) {
    scale *= 10;
  }
  return [for (final b in loan.balances) b.minor / scale];
}
