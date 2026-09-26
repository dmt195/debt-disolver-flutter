import 'package:debt_destroyer/features/loans/domain/loan_calculator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  Money gbp(int minor) => Money(minor, 'GBP');
  LoanSolved solved(LoanResult? r) => r! as LoanSolved;

  test('works out the payment', () {
    final r = solved(
      solveLoan(
        unknown: LoanUnknown.payment,
        amount: gbp(1000000),
        aprBps: 1290,
        months: 60,
      ),
    );
    expect(r.payment, gbp(22343));
    expect(r.totalPaid, gbp(1340570));
    expect(r.totalInterest, gbp(340570));
  });

  test('works out the term', () {
    expect(
      solved(
        solveLoan(
          unknown: LoanUnknown.term,
          amount: gbp(1000000),
          aprBps: 1290,
          payment: gbp(30000),
        ),
      ).months,
      41,
    );
  });

  test('works out the amount', () {
    expect(
      solved(
        solveLoan(
          unknown: LoanUnknown.amount,
          aprBps: 790,
          payment: gbp(25000),
          months: 48,
        ),
      ).balance,
      gbp(1031400),
    );
  });

  test('works out the rate', () {
    expect(
      solved(
        solveLoan(
          unknown: LoanUnknown.rate,
          amount: gbp(1000000),
          payment: gbp(22343),
          months: 60,
        ),
      ).aprBps,
      1290,
    );
  });

  test('says when it never clears', () {
    expect(
      (solveLoan(
                unknown: LoanUnknown.term,
                amount: gbp(120000),
                aprBps: 1200,
                payment: gbp(1139),
              )!
              as LoanImpossible)
          .problem,
      LoanProblem.neverClears,
    );
  });

  test('waits for the other three', () {
    expect(
      solveLoan(unknown: LoanUnknown.payment, amount: gbp(1000000), months: 60),
      isNull,
    );
  });

  test('ignores the figure being worked out', () {
    expect(
      solved(
        solveLoan(
          unknown: LoanUnknown.payment,
          amount: gbp(1000000),
          aprBps: 1290,
          months: 60,
          payment: gbp(1),
        ),
      ).payment,
      gbp(22343),
    );
  });

  test('the balance series, in major units', () {
    final loan = solved(
      solveLoan(
        unknown: LoanUnknown.payment,
        amount: gbp(1000000),
        aprBps: 1290,
        months: 60,
      ),
    );
    final series = loanBalanceSeries(loan);
    expect(series, hasLength(61));
    expect(series.first, 10000.0);
    expect(series.last, 0.0);
  });
}
