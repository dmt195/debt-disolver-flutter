import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('fixedLoanPayment', () {
    test('at 0% it is the balance over the term, rounded up', () {
      expect(
        fixedLoanPayment(balanceMinor: 100000, aprBps: 0, termMonths: 12),
        8334,
      );
    });

    test("uses the engine's own monthly interest and rounding", () {
      expect(
        fixedLoanPayment(balanceMinor: 120000, aprBps: 1200, termMonths: 12),
        10628,
      );
      expect(
        fixedLoanPayment(balanceMinor: 500000, aprBps: 600, termMonths: 60),
        9630,
      );
    });

    test('stays within 64-bit arithmetic at the largest loan', () {
      // 50 * kMaxAmountMinor plus a 20% fee, at 100% APR over 120 months.
      // Exact value from an integer-exact reference model of compound
      // interest (Plan 11), with the same "diverging balance" ceiling rule
      // applied: a too-small
      // trial payment during the search lets the balance grow past 10^13
      // (the ceiling simulate.dart also uses), so the search must give up on
      // that payment rather than keep squaring an ever-larger balance.
      const balanceMinor = 6000000000000;
      const aprBps = 10000;
      const termMonths = 120;
      final payment = fixedLoanPayment(
        balanceMinor: balanceMinor,
        aprBps: aprBps,
        termMonths: termMonths,
      );
      expect(payment, 357126760330);

      // The payment really does clear the loan within the term.
      var balance = balanceMinor;
      var months = 0;
      while (balance > 0 && months < termMonths) {
        balance += monthlyInterest()(balance, aprBps);
        balance -= payment < balance ? payment : balance;
        months++;
      }
      expect(balance, 0);
      expect(months, lessThanOrEqualTo(termMonths));
    });

    test('is the smallest payment that clears within the term', () {
      PayoffPlan loanPaying(int payment) => planOf(
        calculate(
          debts: [
            debt(
              id: 'loan',
              type: DebtType.loan,
              balance: 120000,
              aprBps: 1200,
              minPaymentFloor: payment,
              allowsOverpayment: false,
            ),
          ],
          monthlyBudget: gbp(payment),
          strategy: const Strategy.avalanche(),
        ),
      );
      expect(loanPaying(10628).monthsToClear, 12);
      expect(loanPaying(10627).monthsToClear, 13);
    });
  });

  group('consolidation', () {
    final visa = debt(
      id: 'a',
      name: 'Visa',
      balance: 100000,
      aprBps: 2000,
      minPaymentPercentBps: 300,
      minPaymentFloor: 2500,
    );
    final mum = debt(
      id: 'f',
      name: 'Mum',
      type: DebtType.personal,
      balance: 50000,
      minPaymentFloor: 5000,
    );
    const strategy = Strategy.consolidation(
      aprBps: 600,
      termMonths: 24,
      feeBps: 200,
    );

    // Figures worked out with APR ÷ 12; the subject isn't the rate.
    test(
      'replaces eligible debts with a fixed-payment loan',
      () => nominal(() {
        final r = restructure([visa, mum], strategy) as Restructured;
        final loan = r.debts.first;
        expect(loan.id, kConsolidationDebtId);
        expect(loan.balance, gbp(102000)); // 1,000.00 + 2% fee
        expect(loan.minPaymentPercentBps, 0);
        expect(loan.minPaymentFloor, gbp(4521));
        expect(loan.allowsOverpayment, isTrue);
        expect(r.debts.skip(1), [mum]);
        expect(r.fees, gbp(2000));
        expect(
          r.change,
          PlanChange.consolidation(
            replaced: [
              MovedBalance(debtId: 'a', name: 'Visa', amount: gbp(100000)),
            ],
            fee: gbp(2000),
            monthlyPayment: gbp(4521),
            termMonths: 24,
            aprBps: 600,
          ),
        );
      }),
    );

    // Figures worked out with APR ÷ 12; the subject isn't the rate.
    test(
      'overpays the loan with what the budget has left',
      () => nominal(() {
        final plan = planOf(
          calculate(
            debts: [visa, mum],
            monthlyBudget: gbp(30000),
            strategy: strategy,
          ),
        );
        expect(plan.monthsToClear, 6);
        expect(plan.totalPaid, gbp(153320));
        expect(plan.totalInterest, gbp(1320));
        expect(plan.totalFees, gbp(2000));
        expect(plan.payoffOrder, [kConsolidationDebtId, 'f']);
      }),
    );

    test('is not applicable when nothing can be consolidated', () {
      expect(
        calculate(
          debts: [debt(id: 's', type: DebtType.studentLoan, balance: 100000)],
          monthlyBudget: gbp(10000),
          strategy: strategy,
        ),
        const PayoffResult.notApplicable(
          strategyId: StrategyId.consolidation,
          reason: NotApplicableReason.nothingToConsolidate,
        ),
      );
    });

    test('rejects a term below one month', () {
      expect(
        () => calculate(
          debts: [visa],
          monthlyBudget: gbp(10000),
          strategy: const Strategy.consolidation(aprBps: 600, termMonths: 0),
        ),
        throwsArgumentError,
      );
    });
  });
}
