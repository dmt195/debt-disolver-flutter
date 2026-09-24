import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/payoff_engine.dart';

part 'scenario.freezed.dart';

/// Saved what-if settings (a budget and strategy parameters) applied to the
/// one real debt list. It never holds debts of its own.
@freezed
abstract class Scenario with _$Scenario {
  const factory Scenario({
    required String id,
    required String name,
    required Money monthlyBudget,
    required StrategyParameters parameters,
    required DateTime createdAt,
  }) = _Scenario;
}

enum ScenarioNameError { empty, duplicate }

/// Problems with [name] given the [others] already saved (leave out the
/// scenario being renamed). Names compare ignoring case and outer spaces.
Set<ScenarioNameError> validateScenarioName(
  String name,
  Iterable<Scenario> others,
) {
  final key = name.trim().toLowerCase();
  return {
    if (key.isEmpty) ScenarioNameError.empty,
    if (key.isNotEmpty && others.any((s) => s.name.trim().toLowerCase() == key))
      ScenarioNameError.duplicate,
  };
}
