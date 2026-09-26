import 'package:debt_destroyer/features/debts/domain/loan_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  final now = DateTime(2026, 9, 24);
  Money gbp(int minor) => Money(minor, 'GBP');

  LoanFilled filled(LoanWorkedOut? r) => r! as LoanFilled;
  LoanNotPossible refused(LoanWorkedOut? r) => r! as LoanNotPossible;

  test('works out the monthly payment', () {
    final r = filled(
      workOutLoan(
        balance: gbp(500000),
        aprBps: 690,
        lastPaymentYearMonth: 202909,
        now: now,
      ),
    );
    expect(r.figure, LoanFigure.payment);
    expect(r.payment, gbp(15369));
  });

  test('works out the last payment', () {
    final r = filled(
      workOutLoan(
        balance: gbp(500000),
        aprBps: 690,
        payment: gbp(20000),
        now: now,
      ),
    );
    expect(r.figure, LoanFigure.lastPayment);
    expect(r.lastPaymentYearMonth, 202812); // 27 months after Sep 2026
  });

  test('works out the balance', () {
    final r = filled(
      workOutLoan(
        aprBps: 690,
        payment: gbp(15369),
        lastPaymentYearMonth: 202909,
        now: now,
      ),
    );
    expect(r.figure, LoanFigure.balance);
    expect(r.balance, gbp(500000));
  });

  test('works out the rate', () {
    final r = filled(
      workOutLoan(
        balance: gbp(500000),
        payment: gbp(15369),
        lastPaymentYearMonth: 202909,
        now: now,
      ),
    );
    expect(r.figure, LoanFigure.rate);
    expect(r.aprBps, 690);
  });

  test('needs exactly one missing', () {
    expect(workOutLoan(balance: gbp(500000), aprBps: 690, now: now), isNull);
    expect(
      workOutLoan(
        balance: gbp(500000),
        aprBps: 690,
        payment: gbp(15369),
        lastPaymentYearMonth: 202909,
        now: now,
      ),
      isNull,
    );
  });

  test('a payment no bigger than the interest never clears', () {
    final r = refused(
      workOutLoan(
        balance: gbp(120000),
        aprBps: 1200,
        payment: gbp(1139),
        now: now,
      ),
    );
    expect(r.figure, LoanFigure.payment);
    expect(r.problem, LoanProblem.neverClears);
  });

  test('a last payment this month is out of range', () {
    final r = refused(
      workOutLoan(
        balance: gbp(500000),
        payment: gbp(15369),
        lastPaymentYearMonth: 202609,
        now: now,
      ),
    );
    expect(r.figure, LoanFigure.lastPayment);
    expect(r.problem, LoanProblem.outOfRange);
  });

  test('payments short of the balance', () {
    final r = refused(
      workOutLoan(
        balance: gbp(120000),
        payment: gbp(9999),
        lastPaymentYearMonth: 202709,
        now: now,
      ),
    );
    expect(r.figure, LoanFigure.payment);
    expect(r.problem, LoanProblem.rateBelowZero);
  });

  test('a rate above 100% belongs on the rate', () {
    final r = refused(
      workOutLoan(
        balance: gbp(100000),
        payment: gbp(200000),
        lastPaymentYearMonth: 202610,
        now: now,
      ),
    );
    expect(r.figure, LoanFigure.rate);
    expect(r.problem, LoanProblem.rateTooHigh);
  });
}
