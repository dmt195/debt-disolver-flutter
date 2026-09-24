import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  Scenario named(String name) => Scenario(
    id: name,
    name: name,
    monthlyBudget: const Money(30000, 'GBP'),
    parameters: const StrategyParameters(),
    createdAt: DateTime(2026, 9, 24),
  );

  test('a name must not be empty', () {
    expect(validateScenarioName('  ', const []), {ScenarioNameError.empty});
  });

  test('names are unique, ignoring case and spaces', () {
    expect(validateScenarioName(' bonus ', [named('Bonus')]), {
      ScenarioNameError.duplicate,
    });
    expect(validateScenarioName('Pay rise', [named('Bonus')]), isEmpty);
  });
}
