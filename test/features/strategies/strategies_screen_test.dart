import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  // 1,000.00 at 0% with no minimum, paid at 250.00 a month.
  final simple = testDebt(
    id: 'a',
    name: 'Visa',
    aprBps: 0,
    minPaymentPercentBps: 0,
    minPaymentFloor: 0,
  );

  testWidgets('ranks every strategy and marks the cheapest', (tester) async {
    await pumpApp(
      tester,
      debts: [simple],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    for (final name in [
      'Highest interest first',
      'Lowest interest first',
      'Pay 10% more',
      'Consolidation loan',
      '0% balance transfer',
    ]) {
      await tester.scrollUntilVisible(find.text(name), 100);
      expect(find.text(name), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('Cheapest'), -100);
    expect(find.text('Cheapest'), findsOneWidget);
    // Ties on cost and months fall back to strategy order.
    final cheapestCard = find.ancestor(
      of: find.text('Cheapest'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(
        of: cheapestCard,
        matching: find.text('Highest interest first'),
      ),
      findsOneWidget,
    );
    expect(find.text('Debt-free in 4 months'), findsWidgets);
    expect(find.text('Total paid: £1,000.00'), findsWidgets);
  });

  testWidgets('explains a budget that cannot cover the minimums', (
    tester,
  ) async {
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a')],
      settings: {SettingsKeys.monthlyBudgetMinor: 1000},
      location: Routes.strategies,
    );
    expect(
      find.textContaining('short of the minimum payments in month 1'),
      findsWidgets,
    );
  });

  testWidgets('opens a feasible plan', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [simple],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    await tester.tap(find.text('Highest interest first'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.plan(StrategyId.avalanche));
  });

  testWidgets('with no debts, asks for one', (tester) async {
    await pumpApp(tester, location: Routes.strategies);
    expect(find.text('Add a debt to compare strategies.'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });
}
