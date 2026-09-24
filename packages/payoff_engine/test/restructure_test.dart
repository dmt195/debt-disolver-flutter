import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final low = debt(id: 'low', balance: 1000, aprBps: 500);
  final high = debt(id: 'high', balance: 2000, aprBps: 2000);

  Restructured paid(List<Debt> debts, Strategy strategy) =>
      restructure(debts, strategy, budget: gbp(500)) as Restructured;

  test('direct strategies keep the list as given and add no fees', () {
    for (final s in const [
      Strategy.avalanche(),
      Strategy.snowball(),
      Strategy.customOrder(),
      Strategy.minimumsOnly(),
    ]) {
      final r = paid([low, high], s);
      expect(r.debts, [low, high], reason: '$s');
      expect(r.fees, gbp(0), reason: '$s');
    }
  });

  test('balance transfer is a card with a 0% promo, then the revert APR', () {
    final r = paid(
      [low, high],
      const Strategy.balanceTransfer(
        feeBps: 400,
        promoMonths: 12,
        revertAprBps: 1500,
      ),
    );
    final card = r.debts.single;
    expect(card.id, kBalanceTransferDebtId);
    expect(card.balance, gbp(3120)); // 3,000 + 4%
    expect(card.aprBps, 1500);
    expect(card.promo, const Promo(aprBps: 0, months: 12));
    expect(r.fees, gbp(120));
  });

  test('a transfer with no promo months has no promo', () {
    final r = paid(
      [low],
      const Strategy.balanceTransfer(
        feeBps: 0,
        promoMonths: 0,
        revertAprBps: 1500,
      ),
    );
    expect(r.debts.single.promo, isNull);
  });

  test('does not modify its input', () {
    final input = [low, high];
    restructure(input, const Strategy.avalanche(), budget: gbp(500));
    expect(input, [low, high]);
  });
}
