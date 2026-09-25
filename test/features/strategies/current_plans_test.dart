import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/presentation/current_plans.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/test_container.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = createTestContainer()..listen(homePlanProvider, (_, _) {});
  });

  Future<HomePlan> settled() async {
    await container.pump();
    await container.read(debtsProvider.future);
    return await container.read(homePlanProvider.future);
  }

  // 3,000.00 at 0% with no minimum; the default budget is 300.00.
  Debt interestFree() => testDebt(
    id: '',
    balance: 300000,
    aprBps: 0,
    minPaymentPercentBps: 0,
    minPaymentFloor: 0,
  );

  test('with no debts there is nothing to follow', () async {
    expect(await settled(), isA<HomeNoDebts>());
  });

  test('follows the cheapest way to pay off on Current settings', () async {
    await container.read(debtActionsProvider.notifier).add(interestFree());
    final home = await settled() as HomeFollowing;
    expect(home.result.plan.monthsToClear, 10);
  });

  test('ignores the slider and a selected scenario', () async {
    await container.read(debtActionsProvider.notifier).add(interestFree());
    final saved = await container
        .read(scenarioActionsProvider.notifier)
        .create(
          name: 'Bonus',
          monthlyBudget: const Money(60000, 'GBP'),
          parameters: const StrategyParameters(),
        );
    container
        .read(selectedScenarioIdProvider.notifier)
        .select((saved as ScenarioSaved).scenario.id);
    container.read(extraPaymentProvider.notifier).set(5000);
    final home = await settled() as HomeFollowing;
    expect(home.result.plan.monthsToClear, 10);
  });

  test('a budget below the minimums is a shortfall', () async {
    await container.read(debtActionsProvider.notifier).add(testDebt(id: ''));
    await container
        .read(settingsControllerProvider.notifier)
        .setMonthlyBudget(1000);
    expect(await settled(), isA<HomeShortfall>());
  });
}
