import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/domain/rank_results.dart';
import 'package:flutter/foundation.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'plans_providers.g.dart';

/// Every strategy's result for the current debts and settings, ranked by
/// [rankResults]. Recalculated off the UI thread whenever either changes.
@riverpod
Future<List<PayoffResult>> plans(Ref ref) async {
  final debts = await ref.watch(debtsProvider.future);
  final settings = await ref.watch(settingsControllerProvider.future);
  final results = await compute(_calculateAll, (
    debts,
    settings.monthlyBudget,
    settings.strategyParameters,
  ));
  return rankResults(results);
}

/// One strategy's result, looked up by id.
@riverpod
Future<PayoffResult> plan(Ref ref, StrategyId strategyId) async {
  final all = await ref.watch(plansProvider.future);
  return all.firstWhere((r) => r.strategyId == strategyId);
}

List<PayoffResult> _calculateAll(
  (List<Debt>, Money, StrategyParameters) input,
) => calculateAll(
  debts: input.$1,
  monthlyBudget: input.$2,
  parameters: input.$3,
);
