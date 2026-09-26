import 'package:debt_destroyer/features/debts/domain/promo_dates.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// The four figures of a fixed-payment loan (spec §3.2).
enum LoanFigure { balance, rate, payment, lastPayment }

/// What the loan helper worked out.
sealed class LoanWorkedOut {
  const LoanWorkedOut();
}

/// The missing [figure]'s new value: one of the four fields is set.
final class LoanFilled extends LoanWorkedOut {
  const LoanFilled(
    this.figure, {
    this.balance,
    this.aprBps,
    this.payment,
    this.lastPaymentYearMonth,
  });

  final LoanFigure figure;
  final Money? balance;
  final int? aprBps;
  final Money? payment;

  /// `yyyymm`.
  final int? lastPaymentYearMonth;
}

/// Why it can't be worked out, and which field the message belongs on.
final class LoanNotPossible extends LoanWorkedOut {
  const LoanNotPossible(this.figure, this.problem);

  final LoanFigure figure;
  final LoanProblem problem;
}

/// Works out the one missing figure of [balance], [aprBps], [payment] and
/// [lastPaymentYearMonth] (`yyyymm`) from the other three. Null unless
/// exactly one is missing. A loan's months run from [now]'s month to its
/// last payment, as Home counts a plan's.
LoanWorkedOut? workOutLoan({
  required DateTime now,
  Money? balance,
  int? aprBps,
  Money? payment,
  int? lastPaymentYearMonth,
}) {
  final missing = [
    if (balance == null) LoanFigure.balance,
    if (aprBps == null) LoanFigure.rate,
    if (payment == null) LoanFigure.payment,
    if (lastPaymentYearMonth == null) LoanFigure.lastPayment,
  ];
  if (missing.length != 1) return null;
  final figure = missing.single;

  final months = lastPaymentYearMonth == null
      ? null
      : monthsUntil(lastPaymentYearMonth, now);
  if (months != null && months < 1) {
    return const LoanNotPossible(
      LoanFigure.lastPayment,
      LoanProblem.outOfRange,
    );
  }

  final result = switch (figure) {
    LoanFigure.balance => loanBalance(
      aprBps: aprBps!,
      payment: payment!,
      months: months!,
    ),
    LoanFigure.rate => loanApr(
      balance: balance!,
      payment: payment!,
      months: months!,
    ),
    LoanFigure.payment => loanPayment(
      balance: balance!,
      aprBps: aprBps!,
      months: months!,
    ),
    LoanFigure.lastPayment => loanMonths(
      balance: balance!,
      aprBps: aprBps!,
      payment: payment!,
    ),
  };

  return switch (result) {
    LoanSolved() => switch (figure) {
      LoanFigure.balance => LoanFilled(figure, balance: result.balance),
      LoanFigure.rate => LoanFilled(figure, aprBps: result.aprBps),
      LoanFigure.payment => LoanFilled(figure, payment: result.payment),
      LoanFigure.lastPayment => LoanFilled(
        figure,
        lastPaymentYearMonth: yearMonthAfter(result.months, now),
      ),
    },
    LoanImpossible(:final problem) => LoanNotPossible(switch (problem) {
      LoanProblem.neverClears ||
      LoanProblem.rateBelowZero => LoanFigure.payment,
      LoanProblem.rateTooHigh => LoanFigure.rate,
      LoanProblem.outOfRange => figure,
    }, problem),
  };
}
