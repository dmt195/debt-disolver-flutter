import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/domain/rank_results.dart';
import 'package:debt_destroyer/features/strategies/domain/strategy_groups.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'current_plans.g.dart';

/// Every strategy on the user's own settings: no saved scenario and no
/// "pay more" slider, which are both what-ifs (spec §4.2).
@riverpod
Future<PlanSet> currentPlans(Ref ref) async {
  final debts = await ref.watch(debtsProvider.future);
  final settings = await ref.watch(settingsControllerProvider.future);
  final set = await ref.watch(planCalculatorProvider)(
    debts,
    settings.monthlyBudget,
    settings.strategyParameters,
  );
  return (ranked: rankResults(set.ranked), baseline: set.baseline);
}

/// What Home shows.
sealed class HomePlan {
  const HomePlan();
}

class HomeNoDebts extends HomePlan {
  const HomeNoDebts();
}

/// The plan Home follows, and the minimums-only baseline it beats.
class HomeFollowing extends HomePlan {
  const HomeFollowing(this.result, this.baseline);

  final Feasible result;
  final PayoffResult baseline;
}

/// The budget doesn't cover the minimums; it is [shortfall] short.
class HomeShortfall extends HomePlan {
  const HomeShortfall(this.shortfall);

  final Money shortfall;
}

class HomeNeverClears extends HomePlan {
  const HomeNeverClears();
}

/// The plan Home follows: until the user can choose one (Plan 8), the
/// cheapest way to pay off.
@riverpod
Future<HomePlan> homePlan(Ref ref) async {
  final debts = await ref.watch(debtsProvider.future);
  if (debts.isEmpty) return const HomeNoDebts();
  final set = await ref.watch(currentPlansProvider.future);
  if (bestPayOffMethod(set.ranked) case final best?) {
    return HomeFollowing(best, set.baseline);
  }
  for (final r in set.ranked) {
    if (r case Infeasible(:final shortfall)) return HomeShortfall(shortfall);
  }
  return const HomeNeverClears();
}

/// One strategy's result on Current settings (the baseline included): what
/// Home's chart opens.
@riverpod
Future<PayoffResult> currentPlan(Ref ref, StrategyId strategyId) async {
  final set = await ref.watch(currentPlansProvider.future);
  if (strategyId == StrategyId.minimumsOnly) return set.baseline;
  return set.ranked.firstWhere((r) => r.strategyId == strategyId);
}
