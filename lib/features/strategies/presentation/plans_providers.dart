import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/domain/rank_results.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'plans_providers.g.dart';

/// The ranked strategies and the minimums-only baseline they are compared
/// with.
typedef PlanSet = ({List<PayoffResult> ranked, PayoffResult baseline});

/// Runs every standard strategy and the baseline. The app computes in a
/// background isolate; widget tests substitute a synchronous version
/// because isolates don't run under the test clock.
typedef PlanCalculator = Future<PlanSet> Function(
  List<Debt> debts,
  Money monthlyBudget,
  StrategyParameters parameters,
);

/// Every standard strategy plus the baseline. Pure, so it can run in an
/// isolate.
PlanSet calculatePlanSet(
  List<Debt> debts,
  Money monthlyBudget,
  StrategyParameters parameters,
) => (
  ranked: calculateAll(
    debts: debts,
    monthlyBudget: monthlyBudget,
    parameters: parameters,
  ),
  baseline: calculateBaseline(debts: debts, monthlyBudget: monthlyBudget),
);

@Riverpod(keepAlive: true)
PlanCalculator planCalculator(Ref ref) =>
    (debts, budget, parameters) =>
        compute(_calculatePlanSet, (debts, budget, parameters));

/// Extra paid each month on top of the budget, in minor units: the
/// Strategies screen's "pay more" slider. Kept for the session only, and
/// reset when the currency changes (its minor units would mean something
/// else).
@Riverpod(keepAlive: true)
class ExtraPayment extends _$ExtraPayment {
  @override
  int build() {
    ref.watch(settingsControllerProvider.select((s) => s.value?.currencyCode));
    return 0;
  }

  void set(int minor) => state = minor < 0 ? 0 : minor;
}

/// Every strategy's result for the current debts and settings, ranked by
/// [rankResults], and the baseline. Recalculated whenever either changes.
@riverpod
Future<PlanSet> plans(Ref ref) async {
  final debts = await ref.watch(debtsProvider.future);
  final settings = await ref.watch(settingsControllerProvider.future);
  final budget = settings.monthlyBudget;
  // Never more than the budget again, even if the budget has since shrunk.
  final extra = ref.watch(extraPaymentProvider).clamp(0, budget.minor);
  final set = await ref.watch(planCalculatorProvider)(
    debts,
    budget + Money(extra, budget.currency),
    settings.strategyParameters,
  );
  return (ranked: rankResults(set.ranked), baseline: set.baseline);
}

/// One strategy's result, looked up by id (the baseline included).
@riverpod
Future<PayoffResult> plan(Ref ref, StrategyId strategyId) async {
  final set = await ref.watch(plansProvider.future);
  if (strategyId == StrategyId.minimumsOnly) return set.baseline;
  return set.ranked.firstWhere((r) => r.strategyId == strategyId);
}

PlanSet _calculatePlanSet((List<Debt>, Money, StrategyParameters) input) =>
    calculatePlanSet(input.$1, input.$2, input.$3);
