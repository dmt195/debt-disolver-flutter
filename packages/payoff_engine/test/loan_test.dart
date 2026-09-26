import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

LoanSolved solved(LoanResult r) => r as LoanSolved;

void main() {
  group('loanPayment', () {
    test('the smallest payment that clears within the term', () {
      final r = solved(
        loanPayment(balance: gbp(120000), aprBps: 1200, months: 12),
      );
      expect(r.payment, gbp(10628));
      expect(r.months, 12);
      expect(r.totalPaid, gbp(127530));
      expect(r.totalInterest, gbp(7530));
      expect(r.balances.first, gbp(120000));
      expect(r.balances.last, gbp(0));
      expect(r.balances, hasLength(13));
    });

    test('0% is the balance shared out, rounded up', () {
      expect(
        solved(loanPayment(balance: gbp(1000), aprBps: 0, months: 3)).payment,
        gbp(334),
      );
    });

    test('fixedLoanPayment agrees', () {
      expect(
        fixedLoanPayment(balanceMinor: 120000, aprBps: 1200, termMonths: 12),
        10628,
      );
    });

    test('a loan at this payment clears in the plans in the same month', () {
      final r = solved(
        loanPayment(balance: gbp(500000), aprBps: 690, months: 36),
      );
      final plan = planOf(
        calculate(
          debts: [
            debt(
              id: 'loan',
              type: DebtType.loan,
              balance: 500000,
              aprBps: 690,
              minPaymentFloor: r.payment.minor,
              allowsOverpayment: false,
            ),
          ],
          monthlyBudget: r.payment,
          strategy: const Strategy.avalanche(),
        ),
      );
      expect(plan.monthsToClear, 36);
      expect(plan.totalPaid, r.totalPaid);
    });
  });

  group('loanMonths', () {
    test('counts the payments, the last smaller', () {
      final r = solved(
        loanMonths(balance: gbp(120000), aprBps: 1200, payment: gbp(10000)),
      );
      expect(r.months, 13);
      expect(r.totalPaid, gbp(128012));
    });

    test('a payment no bigger than the first interest never clears', () {
      expect(
        loanMonths(balance: gbp(120000), aprBps: 1200, payment: gbp(1139)),
        isA<LoanImpossible>().having(
          (i) => i.problem,
          'problem',
          LoanProblem.neverClears,
        ),
      );
    });

    test('longer than the engine plans is out of range', () {
      // 1,200.00 at 3% charges 2.96 the first month; paying 2.97 clears,
      // but only after 2,311 months, beyond kMaxMonths.
      expect(
        (loanMonths(balance: gbp(120000), aprBps: 300, payment: gbp(297))
                as LoanImpossible)
            .problem,
        LoanProblem.outOfRange,
      );
    });
  });

  group('loanBalance', () {
    test('the roundest balance with exactly this payment', () {
      final r = solved(
        loanBalance(aprBps: 1200, payment: gbp(10628), months: 12),
      );
      expect(r.balance, gbp(120000));
      expect(r.months, lessThanOrEqualTo(12));
    });

    test('a £5,000 loan reads back as £5,000', () {
      expect(
        solved(
          loanBalance(aprBps: 690, payment: gbp(15369), months: 36),
        ).balance,
        gbp(500000),
      );
    });

    test('at 0% it is payment × months', () {
      expect(
        solved(loanBalance(aprBps: 0, payment: gbp(10000), months: 12)).balance,
        gbp(120000),
      );
    });
  });

  group('loanApr', () {
    test('the roundest APR that gives exactly this payment', () {
      // 106.28 is the payment for 12% (and for a sliver above and below).
      expect(
        solved(
          loanApr(balance: gbp(120000), payment: gbp(10628), months: 12),
        ).aprBps,
        1200,
      );
    });

    for (final (label, balance, apr, months) in [
      ('an interest-free loan reads as 0%', 100000, 0, 12),
      ('19.9% reads as 19.9%', 1000000, 1990, 36),
      ('12.68% reads as 12.68%', 500000, 1268, 24),
      ('exactly 100% is allowed', 100000, 10000, 60),
      ('exactly 100% over ten years', 100000, 10000, 120),
    ]) {
      test(label, () {
        final payment = solved(
          loanPayment(balance: gbp(balance), aprBps: apr, months: months),
        ).payment;
        expect(
          solved(
            loanApr(balance: gbp(balance), payment: payment, months: months),
          ).aprBps,
          apr,
        );
      });
    }

    test('0% when the payments exactly add up to the balance', () {
      expect(
        solved(
          loanApr(balance: gbp(120000), payment: gbp(10000), months: 12),
        ).aprBps,
        0,
      );
    });

    test('payments that add up to less than the balance', () {
      expect(
        (loanApr(balance: gbp(120000), payment: gbp(9999), months: 12)
                as LoanImpossible)
            .problem,
        LoanProblem.rateBelowZero,
      );
    });

    test('a rate above 100%', () {
      // 1,000.00 repaid as 2,000.00 next month is 100% a month.
      expect(
        (loanApr(balance: gbp(100000), payment: gbp(200000), months: 1)
                as LoanImpossible)
            .problem,
        LoanProblem.rateTooHigh,
      );
    });
  });

  group('agree with each other', () {
    for (final (balance, apr, months) in [
      (100, 0, 1),
      (120000, 1200, 12),
      (2500000, 2990, 60),
      (9999999, 10000, 120),
      (50000, 1, 1200),
    ]) {
      test('$balance at $apr over $months', () {
        final byPayment = solved(
          loanPayment(balance: gbp(balance), aprBps: apr, months: months),
        );
        expect(
          solved(
            loanMonths(
              balance: gbp(balance),
              aprBps: apr,
              payment: byPayment.payment,
            ),
          ).months,
          byPayment.months,
        );
        // The balance worked out gives back exactly this payment.
        final byBalance = solved(
          loanBalance(aprBps: apr, payment: byPayment.payment, months: months),
        );
        expect(
          solved(
            loanPayment(
              balance: byBalance.balance,
              aprBps: apr,
              months: months,
            ),
          ).payment,
          byPayment.payment,
        );
        // The rate worked out gives back exactly this payment.
        final byApr = solved(
          loanApr(
            balance: gbp(balance),
            payment: byPayment.payment,
            months: months,
          ),
        );
        expect(
          solved(
            loanPayment(
              balance: gbp(balance),
              aprBps: byApr.aprBps,
              months: months,
            ),
          ).payment,
          byPayment.payment,
        );
      });
    }
  });

  group('inputs out of range', () {
    test('term, amounts and rate', () {
      LoanProblem problem(LoanResult r) => (r as LoanImpossible).problem;
      expect(
        problem(loanPayment(balance: gbp(100), aprBps: 0, months: 0)),
        LoanProblem.outOfRange,
      );
      expect(
        problem(
          loanPayment(balance: gbp(100), aprBps: 0, months: kMaxMonths + 1),
        ),
        LoanProblem.outOfRange,
      );
      expect(
        problem(loanPayment(balance: gbp(0), aprBps: 0, months: 12)),
        LoanProblem.outOfRange,
      );
      expect(
        problem(
          loanPayment(balance: gbp(kMaxAmountMinor + 1), aprBps: 0, months: 12),
        ),
        LoanProblem.outOfRange,
      );
      expect(
        problem(loanPayment(balance: gbp(100), aprBps: 10001, months: 12)),
        LoanProblem.outOfRange,
      );
    });
  });
}
