import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'scenarios_providers.freezed.dart';
part 'scenarios_providers.g.dart';

/// Saved scenarios, oldest first, labelled with the current currency. Stays
/// loading until settings have loaded.
@Riverpod(keepAlive: true)
Stream<List<Scenario>> scenarios(Ref ref) {
  final (currencyCode, error) = ref.watch(
    settingsControllerProvider.select((s) => (s.value?.currencyCode, s.error)),
  );
  if (error != null) return Stream.error(error);
  if (currencyCode == null) return const Stream.empty();
  return ref.watch(scenarioRepositoryProvider).watchAll(currencyCode);
}

@freezed
sealed class ScenarioSaveOutcome with _$ScenarioSaveOutcome {
  const factory ScenarioSaveOutcome.saved(Scenario scenario) = ScenarioSaved;

  const factory ScenarioSaveOutcome.rejected({
    @Default(<ScenarioNameError>{}) Set<ScenarioNameError> nameErrors,
    @Default(<BudgetValidationError>{}) Set<BudgetValidationError> budgetErrors,
    @Default(<StrategyParametersValidationError>{})
    Set<StrategyParametersValidationError> parameterErrors,
  }) = ScenarioRejected;
}

/// Validated changes to the saved scenarios.
@Riverpod(keepAlive: true)
class ScenarioActions extends _$ScenarioActions {
  static const _uuid = Uuid();

  /// The change in progress; each new one waits for it, so a name check and
  /// its write can't interleave with another.
  Future<void> _pending = Future<void>.value();

  @override
  void build() {}

  /// Saves a new scenario.
  Future<ScenarioSaveOutcome> create({
    required String name,
    required Money monthlyBudget,
    required StrategyParameters parameters,
  }) => _serialised(
    () => _save(
      Scenario(
        id: _uuid.v4(),
        name: name.trim(),
        monthlyBudget: monthlyBudget,
        parameters: parameters,
        createdAt: ref.read(clockProvider)(),
      ),
    ),
  );

  /// Replaces the saved scenario with [scenario]'s id.
  Future<ScenarioSaveOutcome> update(Scenario scenario) =>
      _serialised(() => _save(scenario.copyWith(name: scenario.name.trim())));

  Future<void> delete(String id) =>
      _serialised(() => ref.read(scenarioRepositoryProvider).delete(id));

  Future<ScenarioSaveOutcome> _save(Scenario scenario) async {
    final settings = await ref.read(settingsControllerProvider.future);
    final repository = ref.read(scenarioRepositoryProvider);
    final others = (await repository.loadAll(settings.currencyCode))
        .where((s) => s.id != scenario.id);
    final nameErrors = validateScenarioName(scenario.name, others);
    final budgetErrors = validateBudget(scenario.monthlyBudget);
    final parameterErrors = validateStrategyParameters(scenario.parameters);
    if (nameErrors.isNotEmpty ||
        budgetErrors.isNotEmpty ||
        parameterErrors.isNotEmpty) {
      return ScenarioSaveOutcome.rejected(
        nameErrors: nameErrors,
        budgetErrors: budgetErrors,
        parameterErrors: parameterErrors,
      );
    }
    await repository.save(scenario);
    return ScenarioSaveOutcome.saved(scenario);
  }

  Future<T> _serialised<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}
