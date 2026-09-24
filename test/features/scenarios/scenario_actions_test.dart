import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/test_container.dart';

void main() {
  late ProviderContainer container;
  ScenarioActions actions() => container.read(scenarioActionsProvider.notifier);
  Future<List<Scenario>> stored() =>
      container.read(scenarioRepositoryProvider).loadAll('GBP');

  setUp(() => container = createTestContainer());

  Future<ScenarioSaveOutcome> create(String name, {int budget = 45000}) =>
      actions().create(
        name: name,
        monthlyBudget: Money(budget, 'GBP'),
        parameters: const StrategyParameters(),
      );

  test(
    'creates a scenario with a new id, trimmed name and the clock',
    () async {
      final saved = ((await create(' Bonus ')) as ScenarioSaved).scenario;
      expect(saved.id, isNotEmpty);
      expect(saved.name, 'Bonus');
      expect(saved.createdAt, DateTime(2026, 9, 24));
      expect(await stored(), [saved]);
    },
  );

  test('rejects an empty or duplicate name', () async {
    await create('Bonus');
    expect(
      await create(''),
      const ScenarioSaveOutcome.rejected(nameErrors: {ScenarioNameError.empty}),
    );
    expect(
      await create('BONUS'),
      const ScenarioSaveOutcome.rejected(
        nameErrors: {ScenarioNameError.duplicate},
      ),
    );
    expect(await stored(), hasLength(1));
  });

  test('rejects an invalid budget', () async {
    expect(
      await create('Zero', budget: 0),
      const ScenarioSaveOutcome.rejected(
        budgetErrors: {BudgetValidationError.notPositive},
      ),
    );
  });

  test('an update may keep its own name', () async {
    final saved = ((await create('Bonus')) as ScenarioSaved).scenario;
    final outcome = await actions().update(
      saved.copyWith(monthlyBudget: const Money(50000, 'GBP')),
    );
    expect(outcome, isA<ScenarioSaved>());
    expect((await stored()).single.monthlyBudget, const Money(50000, 'GBP'));
  });

  test('delete removes it', () async {
    final saved = ((await create('Bonus')) as ScenarioSaved).scenario;
    await actions().delete(saved.id);
    expect(await stored(), isEmpty);
  });
}
