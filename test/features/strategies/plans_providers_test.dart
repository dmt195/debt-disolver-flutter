import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
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
  Future<List<PayoffResult>> settledPlans() async {
    await container.pump();
    await container.read(debtsProvider.future);
    return await container.read(plansProvider.future);
  }

  test('with no debts every strategy is an empty feasible plan', () async {
    final plans = await settledPlans();
    expect(plans, hasLength(5));
    for (final result in plans) {
      expect((result as Feasible).plan.monthsToClear, 0);
    }
  });

  test('recalculates when a debt is added, cheapest first', () async {
    await container.read(debtActionsProvider.notifier).add(testDebt(id: ''));
    final plans = await settledPlans();
    final costs = [for (final r in plans) (r as Feasible).plan.totalPaid.minor];
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
    expect(avalanche(before), isA<Feasible>());
    // 10.00 no longer covers the 25.00 minimum.
    expect(avalanche(after), isA<Infeasible>());
  });

  test('plan looks up one strategy by id', () async {
    container.listen(planProvider(StrategyId.consolidation), (_, _) {});
    final result = await container.read(
      planProvider(StrategyId.consolidation).future,
    );
    expect(result.strategyId, StrategyId.consolidation);
  });
}
