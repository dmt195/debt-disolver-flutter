import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
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

  final bonus = Scenario(
    id: 's1',
    name: 'Bonus',
    monthlyBudget: const Money(50000, 'GBP'),
    parameters: const StrategyParameters(),
    createdAt: DateTime(2026, 9),
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
      'Smallest balance first',
      'Your order',
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

  testWidgets('says why a strategy does not apply', (tester) async {
    await pumpApp(
      tester,
      debts: [simple], // 0% card: nothing worth transferring
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    const reason =
        'Not available: there are no card balances with interest to move.';
    await tester.scrollUntilVisible(find.text(reason), 100);
    expect(find.text(reason), findsOneWidget);
  });

  testWidgets('says when the transfer assumes a credit limit', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [testDebt(id: 'a')], // 1,000.00 at 19.9%
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.strategies,
    );
    // 1,000.00 plus the 4% fee.
    const note = 'Assumes a £1,040.00 credit limit.';
    await tester.scrollUntilVisible(find.text(note), 100);
    await tester.pumpAndSettle();
    expect(find.text(note), findsOneWidget);
    await tester.tap(find.text('Set yours'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.settings);
  });

  testWidgets('compares each plan with paying only the minimums', (
    tester,
  ) async {
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a')], // 1,000.00 at 19.9%, min 3% or 25.00
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.strategies,
    );
    expect(
      find.text('Minimums only: 5 years 2 months · £587.88 interest'),
      findsOneWidget,
    );
    // Highest interest first: 1,037.82 over 4 months against 1,587.88 over 62.
    // (With a single debt, several strategies tie, so more than one card
    // shows this text; scroll to the first.)
    await tester.scrollUntilVisible(
      find
          .text('Saves £550.06 · 4 years 10 months sooner than minimums only')
          .first,
      100,
    );
    expect(
      find.text('Saves £550.06 · 4 years 10 months sooner than minimums only'),
      findsWidgets,
    );
  });

  testWidgets('shows no savings for a plan that costs more', (tester) async {
    await pumpApp(
      tester,
      // 0%, and the minimum is the whole budget: nothing can beat it.
      debts: [
        testDebt(
          id: 'a',
          aprBps: 0,
          minPaymentPercentBps: 0,
          minPaymentFloor: 25000,
        ),
      ],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    expect(
      find.text('Minimums only: 4 months · £0.00 interest'),
      findsOneWidget,
    );
    expect(find.textContaining('Saves'), findsNothing);
    expect(find.textContaining('-£'), findsNothing);
  });

  testWidgets('says when minimums alone never clear the debts', (tester) async {
    await pumpApp(
      tester,
      debts: [simple], // no minimum payment at all
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    expect(
      find.text('Paying only the minimums would never clear these debts.'),
      findsOneWidget,
    );
    expect(
      find.text('Clears your debts; minimums alone never would'),
      findsWidgets,
    );
  });

  testWidgets('opens the baseline plan', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [testDebt(id: 'a')],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.strategies,
    );
    await tester.tap(find.byKey(const ValueKey('baseline')));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.plan(StrategyId.minimumsOnly));
    expect(find.text('Debt-free in 5 years 2 months'), findsOneWidget);
  });

  testWidgets('the slider pays more each month', (tester) async {
    await pumpApp(
      tester,
      debts: [simple], // 1,000.00 at 0%
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    expect(find.text('Pay £0.00 more a month'), findsOneWidget);
    // £5 steps up to £250; the middle of the track is £125.
    await tester.tap(find.byKey(const ValueKey('payMore')));
    await tester.pumpAndSettle();
    expect(find.text('Pay £125.00 more a month'), findsOneWidget);
    expect(find.text('£375.00 a month in total'), findsOneWidget);
    expect(find.text('Debt-free in 3 months'), findsWidgets);
  });

  testWidgets('shows plans for a chosen scenario', (tester) async {
    await pumpApp(
      tester,
      debts: [simple],
      scenarios: [bonus],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    expect(find.text('Debt-free in 4 months'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('scenario')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bonus').last);
    await tester.pumpAndSettle();
    expect(find.text('Debt-free in 2 months'), findsWidgets);
  });

  testWidgets('saves the slider as a scenario and switches to it', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      debts: [simple],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    await tester.tap(find.byKey(const ValueKey('payMore'))); // +£125
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as scenario'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('scenarioName')), 'Bonus');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final saved = app.scenarios.stored.single;
    expect(saved.name, 'Bonus');
    expect(saved.monthlyBudget, const Money(37500, 'GBP'));
    expect(find.text('Scenario saved'), findsOneWidget);
    // Now on the saved scenario: its budget includes the extra.
    expect(find.text('Pay £0.00 more a month'), findsOneWidget);
    expect(find.text('Debt-free in 3 months'), findsWidgets);
  });

  testWidgets('a duplicate name is explained in the dialog', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [simple],
      scenarios: [bonus],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    await tester.tap(find.text('Save as scenario'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('scenarioName')), 'bonus');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('You already have a scenario with that name'),
      findsOneWidget,
    );
    expect(app.scenarios.stored, hasLength(1));
  });

  testWidgets('opens the scenarios screen', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [simple],
      location: Routes.strategies,
    );
    await tester.tap(find.byTooltip('Scenarios'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.scenarios);
  });

  testWidgets('the limit link edits the scenario being viewed', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [testDebt(id: 'a')],
      scenarios: [bonus],
      location: Routes.strategies,
    );
    await tester.tap(find.byKey(const ValueKey('scenario')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bonus').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Set yours'), 100);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set yours'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.editScenario('s1'));
  });
}
