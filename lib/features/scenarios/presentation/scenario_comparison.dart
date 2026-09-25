import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/domain/rank_results.dart';
import 'package:debt_destroyer/features/strategies/domain/strategy_groups.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'scenario_comparison.g.dart';

/// One row of the Compare tab: a scenario (a null id and name for Current)
/// and its cheapest way to pay off (borrowing alternatives aside), or null
/// if none clears the debts.
typedef ScenarioComparison = ({String? id, String? name, Feasible? best});

/// Current, then every saved scenario, each with its best pay-off method.
@riverpod
Future<List<ScenarioComparison>> scenarioComparison(Ref ref) async {
  final debts = await ref.watch(debtsProvider.future);
  final settings = await ref.watch(settingsControllerProvider.future);
  final saved = await ref.watch(scenariosProvider.future);
  final calculate = ref.watch(planCalculatorProvider);

  Future<Feasible?> best(Money budget, StrategyParameters parameters) async {
    final set = await calculate(debts, budget, parameters);
    // Borrowing alternatives are never presented as the best plan.
    return bestPayOffMethod(rankResults(set.ranked));
  }

  return [
    (
      id: null,
      name: null,
      best: await best(settings.monthlyBudget, settings.strategyParameters),
    ),
    for (final s in saved)
      (id: s.id, name: s.name, best: await best(s.monthlyBudget, s.parameters)),
  ];
}
