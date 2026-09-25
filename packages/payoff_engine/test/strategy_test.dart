import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

void main() {
  test('each strategy reports its id', () {
    expect(const Strategy.avalanche().id, StrategyId.avalanche);
    expect(const Strategy.snowball().id, StrategyId.snowball);
    expect(const Strategy.customOrder().id, StrategyId.customOrder);
    expect(const Strategy.cardTransfers().id, StrategyId.cardTransfers);
    expect(const Strategy.minimumsOnly().id, StrategyId.minimumsOnly);
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

  test('standardStrategies lists the six ranked strategies in order', () {
    final ids = standardStrategies(const StrategyParameters()).map((s) => s.id);
    expect(ids, [
      StrategyId.avalanche,
      StrategyId.snowball,
      StrategyId.customOrder,
      StrategyId.cardTransfers,
      StrategyId.consolidation,
      StrategyId.balanceTransfer,
    ]);
  });
}
