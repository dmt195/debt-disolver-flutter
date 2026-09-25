import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/test_container.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    // Providers with no listener are paused; keep plans (and so debts) live.
    container = createTestContainer()..listen(plansProvider, (_, _) {});
  });

  /// Waits for the plans to reflect the latest debts and settings.
  Future<PlanSet> settledPlans() async {
    await container.pump();
    await container.read(debtsProvider.future);
    return await container.read(plansProvider.future);
  }

  // 3,000.00 at 0% with no minimum; the default budget is 300.00.
  Debt interestFree() => testDebt(
    id: '',
    balance: 300000,
    aprBps: 0,
    minPaymentPercentBps: 0,
    minPaymentFloor: 0,
  );
  int avalancheMonths(PlanSet plans) => (plans.ranked.firstWhere(
    (r) => r.strategyId == StrategyId.avalanche,
  ) as Feasible).plan.monthsToClear;

  test('with no debts every strategy is an empty feasible plan', () async {
    final plans = await settledPlans();
    expect(plans.ranked, hasLength(6));
    for (final result in plans.ranked) {
      expect((result as Feasible).plan.monthsToClear, 0);
    }
  });

  test('recalculates when a debt is added, cheapest first', () async {
    await container.read(debtActionsProvider.notifier).add(testDebt(id: ''));
    final plans = await settledPlans();
    // cardTransfers is not applicable: testDebt has no transfer offer. Every
    // other strategy must still be feasible.
    final costs = [
      for (final r in plans.ranked)
        if (r.strategyId != StrategyId.cardTransfers)
          (r as Feasible).plan.totalPaid.minor,
    ];
    expect(costs.first, greaterThan(100000));
    expect(costs, [...costs]..sort());
  });

  test('recalculates when the budget changes', () async {
    await container.read(debtActionsProvider.notifier).add(testDebt(id: ''));
    final before = await settledPlans();
    await container
        .read(settingsControllerProvider.notifier)
        .setMonthlyBudget(1000);
    final after = await settledPlans();
    PayoffResult avalanche(List<PayoffResult> r) =>
        r.firstWhere((p) => p.strategyId == StrategyId.avalanche);
    expect(avalanche(before.ranked), isA<Feasible>());
    // 10.00 no longer covers the 25.00 minimum.
    expect(avalanche(after.ranked), isA<Infeasible>());
  });

  test('plan looks up one strategy by id', () async {
    container.listen(planProvider(StrategyId.consolidation), (_, _) {});
    final result = await container.read(
      planProvider(StrategyId.consolidation).future,
    );
    expect(result.strategyId, StrategyId.consolidation);
  });

  test('includes the minimums-only baseline', () async {
    await container.read(debtActionsProvider.notifier).add(testDebt(id: ''));
    final plans = await settledPlans();
    expect(plans.baseline.strategyId, StrategyId.minimumsOnly);
    expect((plans.baseline as Feasible).plan.monthsToClear, 62);
  });

  test('plan finds the baseline by id', () async {
    container.listen(planProvider(StrategyId.minimumsOnly), (_, _) {});
    final result = await container.read(
      planProvider(StrategyId.minimumsOnly).future,
    );
    expect(result.strategyId, StrategyId.minimumsOnly);
  });

  group('extra payment', () {
    test('is added to the budget', () async {
      await container.read(debtActionsProvider.notifier).add(interestFree());
      container.read(extraPaymentProvider.notifier).set(20000);
      expect(avalancheMonths(await settledPlans()), 6); // 500.00 a month
    });

    test('is capped at the budget', () async {
      await container.read(debtActionsProvider.notifier).add(interestFree());
      container.read(extraPaymentProvider.notifier).set(1000000);
      expect(avalancheMonths(await settledPlans()), 5); // 600.00, not 10,300
    });

    test('resets when the currency changes', () async {
      container.read(extraPaymentProvider.notifier).set(5000);
      await container
          .read(settingsControllerProvider.notifier)
          .setCurrency('JPY');
      expect(container.read(extraPaymentProvider), 0);
    });
  });

  group('scenarios', () {
    Future<Scenario> saveBonus() async =>
        ((await container
                    .read(scenarioActionsProvider.notifier)
                    .create(
                      name: 'Bonus',
                      monthlyBudget: const Money(60000, 'GBP'),
                      parameters: const StrategyParameters(),
                    ))
                as ScenarioSaved)
            .scenario;

    test("plans use the selected scenario's budget", () async {
      await container.read(debtActionsProvider.notifier).add(interestFree());
      final bonus = await saveBonus();
      container.read(selectedScenarioIdProvider.notifier).select(bonus.id);
      expect(avalancheMonths(await settledPlans()), 5); // 600.00 a month
    });

    test('choosing a scenario resets the extra payment', () async {
      final bonus = await saveBonus();
      container.read(extraPaymentProvider.notifier).set(5000);
      container.read(selectedScenarioIdProvider.notifier).select(bonus.id);
      expect(container.read(extraPaymentProvider), 0);
    });

    test('deleting the selected scenario falls back to Current', () async {
      await container.read(debtActionsProvider.notifier).add(interestFree());
      final bonus = await saveBonus();
      container.read(selectedScenarioIdProvider.notifier).select(bonus.id);
      await container.read(scenarioActionsProvider.notifier).delete(bonus.id);
      expect(container.read(selectedScenarioIdProvider), isNull);
      expect(avalancheMonths(await settledPlans()), 10); // 300.00 a month
    });
  });
}
