import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

void main() {
  test('each strategy reports its id', () {
    expect(const Strategy.avalanche().id, StrategyId.avalanche);
    expect(const Strategy.lowestAprFirst().id, StrategyId.lowestAprFirst);
    expect(const Strategy.boosted().id, StrategyId.boosted);
    expect(
      const Strategy.consolidation(aprBps: 400).id,
      StrategyId.consolidation,
    );
    expect(
      const Strategy.balanceTransfer(
        feeBps: 400,
        promoMonths: 15,
        revertAprBps: 1500,
      ).id,
      StrategyId.balanceTransfer,
    );
  });

  test('default parameters match the legacy Settings-screen defaults', () {
    const p = StrategyParameters();
    expect(p.consolidationAprBps, 500);
    expect(p.transferFeeBps, 400);
    expect(p.promoMonths, 12);
    expect(p.revertAprBps, 1500);
  });

  test('standardStrategies lists all five in display order', () {
    final ids = standardStrategies(const StrategyParameters()).map((s) => s.id);
    expect(ids, StrategyId.values);
  });

  test('boosted defaults to 110% of the budget', () {
    const boosted = Strategy.boosted() as Boosted;
    expect(boosted.budgetPercent, 110);
  });
}
