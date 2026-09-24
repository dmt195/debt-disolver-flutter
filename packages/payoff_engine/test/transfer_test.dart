import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final visa = debt(
    id: 'a',
    name: 'Visa',
    balance: 100000,
    aprBps: 2000,
    minPaymentPercentBps: 300,
    minPaymentFloor: 2500,
  );
  final store = debt(
    id: 'b',
    name: 'Store',
    type: DebtType.storeCard,
    balance: 50000,
    aprBps: 2500,
    minPaymentPercentBps: 300,
    minPaymentFloor: 2500,
  );
  final carLoan = debt(
    id: 'l',
    name: 'Car loan',
    type: DebtType.loan,
    balance: 200000,
    aprBps: 700,
    minPaymentFloor: 15000,
  );
  final debts = [visa, store, carLoan];

  Strategy transfer({Money? limit, int promoMonths = 12}) =>
      Strategy.balanceTransfer(
        feeBps: 300,
        promoMonths: promoMonths,
        revertAprBps: 1900,
        creditLimit: limit,
      );

  Restructured restructured(Strategy s, [List<Debt>? input]) =>
      restructure(input ?? debts, s) as Restructured;

  test('with no limit, every card balance moves, highest APR first', () {
    final r = restructured(transfer());
    final card = r.debts.first;
    expect(card.id, kBalanceTransferDebtId);
    // 1,500.00 moved, plus 3% fees of 15.00 (store) and 30.00 (Visa).
    expect(card.balance, gbp(154500));
    expect(r.debts.skip(1), [carLoan]);
    expect(r.fees, gbp(4500));
    expect(
      r.change,
      PlanChange.transfer(
        moved: [
          MovedBalance(debtId: 'b', name: 'Store', amount: gbp(50000)),
          MovedBalance(debtId: 'a', name: 'Visa', amount: gbp(100000)),
        ],
        fee: gbp(4500),
        creditLimit: gbp(154500),
        limitAssumed: true,
        promoMonths: 12,
      ),
    );
  });

  test('the card is 0% for the promo, then the revert APR, 3% minimum', () {
    final card = restructured(transfer()).debts.first;
    expect(card.promo, const Promo(aprBps: 0, months: 12));
    expect(card.aprBps, 1900);
    expect(card.minPaymentPercentBps, kTransferCardMinimumBps);
    expect(card.minPaymentFloor, gbp(0));
    expect(card.allowsOverpayment, isTrue);
  });

  test('a limit moves part of a balance; the fee counts against it', () {
    final r = restructured(transfer(limit: gbp(100000)));
    // Store: 500.00 + 15.00 fee leaves 485.00 of room. Visa: 470.87 plus a
    // 14.13 fee fills it exactly; 470.88 would need 485.01.
    expect(r.debts.first.balance, gbp(100000));
    expect(r.fees, gbp(2913));
    expect(r.debts.skip(1).map((d) => (d.id, d.balance)), [
      ('a', gbp(52913)),
      ('l', gbp(200000)),
    ]);
    final change = r.change! as TransferChange;
    expect(change.limitAssumed, isFalse);
    expect(change.creditLimit, gbp(100000));
  });

  test('skips a balance already on a 0% promo', () {
    final onPromo = visa.copyWith(promo: const Promo(aprBps: 0, months: 6));
    final r = restructured(transfer(), [onPromo, store]);
    expect((r.change! as TransferChange).moved.map((m) => m.debtId), ['b']);
    expect(r.debts.skip(1), [onPromo]);
  });

  test('no promo months means no promo on the card', () {
    expect(restructured(transfer(promoMonths: 0)).debts.first.promo, isNull);
  });

  test('is not applicable when no balance can move', () {
    expect(
      calculate(
        debts: [carLoan],
        monthlyBudget: gbp(60000),
        strategy: transfer(),
      ),
      const PayoffResult.notApplicable(
        strategyId: StrategyId.balanceTransfer,
        reason: NotApplicableReason.noTransferableBalances,
      ),
    );
  });

  test('pays the other debts first while the card is at 0%', () {
    final plan = planOf(
      calculate(debts: debts, monthlyBudget: gbp(60000), strategy: transfer()),
    );
    expect(plan.monthsToClear, 6);
    expect(plan.totalPaid, gbp(357260));
    expect(plan.totalInterest, gbp(2760));
    expect(plan.totalFees, gbp(4500));
    expect(plan.payoffOrder, ['l', kBalanceTransferDebtId]);
    expect(plan.change, isA<TransferChange>());
  });

  test('a partial transfer leaves the rest on the original card', () {
    final plan = planOf(
      calculate(
        debts: debts,
        monthlyBudget: gbp(60000),
        strategy: transfer(limit: gbp(100000)),
      ),
    );
    expect(plan.monthsToClear, 6);
    expect(plan.totalPaid, gbp(357744));
    expect(plan.totalInterest, gbp(4831));
    expect(plan.totalFees, gbp(2913));
    expect(plan.payoffOrder, ['a', 'l', kBalanceTransferDebtId]);
  });

  test('rejects a credit limit in another currency', () {
    expect(
      () => calculate(
        debts: debts,
        monthlyBudget: gbp(60000),
        strategy: transfer(limit: const Money(100000, 'USD')),
      ),
      throwsArgumentError,
    );
  });
}
