import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/screen_names.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../helpers/debts.dart';
import '../helpers/fake_diagnostics.dart';
import '../helpers/pump_app.dart';

void main() {
  test('every route has a name, and no name carries an id', () {
    const expected = {
      '/': 'home',
      '/debts': 'debts',
      '/debts/new': 'debt_new',
      '/debts/:debtId': 'debt_edit',
      '/plans': 'plans',
      '/plans/scenarios': 'scenarios',
      '/plans/scenarios/:scenarioId': 'scenario_edit',
      '/plans/loan-calculator': 'loan_calculator',
      '/plans/:strategyId': 'plan_detail',
      '/settings': 'settings',
      '/onboarding': 'onboarding',
      '/check-in': 'check_in',
      '/check-in/result': 'check_in_result',
      '/cleared/:debtId': 'celebration',
      '/debt-free': 'debt_free',
    };
    for (final MapEntry(key: template, value: name) in expected.entries) {
      expect(screenNameFor(template), name, reason: template);
    }
    expect(screenNameFor('/somewhere/else'), 'other');
    expect(screenNameFor(null), 'other');
  });

  testWidgets('screen views are logged by route, never by id', (tester) async {
    final fake = FakeDiagnostics();
    final app = await pumpApp(
      tester,
      debts: [testDebt(id: 'abc')],
      diagnostics: fake,
    );
    await app.router.go(tester, Routes.plan(StrategyId.avalanche));
    expect(fake.screens.last, 'plan_detail');
    await app.router.go(tester, Routes.editDebt('abc'));
    expect(fake.screens.last, 'debt_edit');
    expect(fake.screens.join(' '), isNot(contains('abc')));
    expect(fake.screens.join(' '), isNot(contains('avalanche')));
  });
}
