import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/charts/balance_line_chart.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

/// A strategy's name on its card (the race chart's legend repeats it).
Finder inCard(String text) => find.descendant(
  of: find.byWidgetPredicate((w) => w is Card && w.key is ValueKey<StrategyId>),
  matching: find.text(text),
);

/// Opens the collapsed borrowing alternatives.
Future<void> showAlternatives(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('Show alternatives'), 100);
  await tester.ensureVisible(find.text('Show alternatives'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Show alternatives'));
  await tester.pumpAndSettle();
}

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

  // Store card: 1,000.00 at 29.9%. Amex: 500.00 at 12.7% with an offer of
  // 0% for 12 months, 3% fee and 2,000.00 of room: all of the store
  // balance moves (1,000.00 + 30.00 fee).
  final store = testDebt(
    id: 's',
    name: 'Store',
    type: DebtType.storeCard,
    aprBps: 2990,
  );
  final amex = testDebt(
    id: 'a',
    name: 'Amex',
    balance: 50000,
    aprBps: 1270,
    transferOffer: const TransferOffer(
      feeBps: 300,
      promo: Promo(aprBps: 0, months: 12),
      availableCredit: Money(200000, 'GBP'),
    ),
  );

  testWidgets('ranks every strategy and marks the cheapest', (tester) async {
    useTallScreen(tester);
    await pumpApp(
      tester,
      debts: [simple],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.plans,
    );
    await showAlternatives(tester);
    for (final name in [
      'Highest interest first',
      'Smallest balance first',
      'Your order',
      'Consolidation loan',
      '0% balance transfer',
    ]) {
      await tester.scrollUntilVisible(inCard(name), 100);
      expect(inCard(name), findsOneWidget);
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
        matching: inCard('Highest interest first'),
      ),
      findsOneWidget,
    );
    expect(find.text('Debt-free in 4 months'), findsWidgets);
    expect(find.text('Total paid: £1,000.00'), findsWidgets);
  });

  testWidgets('explains a budget that cannot cover the minimums', (
    tester,
  ) async {
    useTallScreen(tester);
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a')],
      settings: {SettingsKeys.monthlyBudgetMinor: 1000},
      location: Routes.plans,
    );
    expect(
      find.textContaining('short of the minimum payments in month 1'),
      findsWidgets,
    );
  });

  testWidgets('opens a feasible plan', (tester) async {
    useTallScreen(tester);
    final app = await pumpApp(
      tester,
      debts: [simple],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.plans,
    );
    await tester.tap(inCard('Highest interest first'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.plan(StrategyId.avalanche));
  });

  testWidgets('with no debts, asks for one', (tester) async {
    useTallScreen(tester);
    await pumpApp(tester, location: Routes.plans);
    expect(find.text('Add a debt to see your plans.'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('says why a strategy does not apply', (tester) async {
    useTallScreen(tester);
    await pumpApp(
      tester,
      debts: [simple], // 0% card: nothing worth transferring
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.plans,
    );
    const reason =
        'Not available: there are no card balances with interest to move.';
    await showAlternatives(tester);
    await tester.scrollUntilVisible(find.text(reason), 100);
    expect(find.text(reason), findsOneWidget);
  });

  testWidgets('says when the transfer assumes a credit limit', (tester) async {
    useTallScreen(tester);
    final app = await pumpApp(
      tester,
      debts: [testDebt(id: 'a')], // 1,000.00 at 19.9%
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plans,
    );
    await showAlternatives(tester);
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
    useTallScreen(tester);
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a')], // 1,000.00 at 19.9%, min 3% or 25.00
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plans,
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
    useTallScreen(tester);
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
      location: Routes.plans,
    );
    expect(
      find.text('Minimums only: 4 months · £0.00 interest'),
      findsOneWidget,
    );
    expect(find.textContaining('Saves'), findsNothing);
    expect(find.textContaining('-£'), findsNothing);
  });

  testWidgets('says when minimums alone never clear the debts', (tester) async {
    useTallScreen(tester);
    await pumpApp(
      tester,
      debts: [simple], // no minimum payment at all
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.plans,
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
    useTallScreen(tester);
    final app = await pumpApp(
      tester,
      debts: [testDebt(id: 'a')],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plans,
    );
    await tester.tap(find.byKey(const ValueKey('baseline')));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.plan(StrategyId.minimumsOnly));
    // 5 years 2 months from 24 Sep 2026.
    expect(find.text('November 2031'), findsOneWidget);
    expect(find.text('62'), findsOneWidget);
  });

  testWidgets('the slider pays more each month', (tester) async {
    useTallScreen(tester);
    await pumpApp(
      tester,
      debts: [simple], // 1,000.00 at 0%
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.plans,
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
    useTallScreen(tester);
    await pumpApp(
      tester,
      debts: [simple],
      scenarios: [bonus],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.plans,
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
    useTallScreen(tester);
    final app = await pumpApp(
      tester,
      debts: [simple],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.plans,
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
    useTallScreen(tester);
    final app = await pumpApp(
      tester,
      debts: [simple],
      scenarios: [bonus],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.plans,
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
    useTallScreen(tester);
    final app = await pumpApp(tester, debts: [simple], location: Routes.plans);
    await tester.tap(find.byTooltip('Scenarios'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.scenarios);
  });

  testWidgets('the limit link edits the scenario being viewed', (tester) async {
    useTallScreen(tester);
    final app = await pumpApp(
      tester,
      debts: [testDebt(id: 'a')],
      scenarios: [bonus],
      location: Routes.plans,
    );
    await tester.tap(find.byKey(const ValueKey('scenario')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bonus').last);
    await tester.pumpAndSettle();
    await showAlternatives(tester);
    await tester.scrollUntilVisible(find.text('Set yours'), 100);
    await tester.ensureVisible(find.text('Set yours'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set yours'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.editScenario('s1'));
  });

  testWidgets('separates pay-off methods from borrowing alternatives', (
    tester,
  ) async {
    useTallScreen(tester);
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a')], // 1,000.00 at 19.9%
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plans,
    );
    await tester.scrollUntilVisible(
      find.text('Ways to pay off your debts'),
      100,
    );
    expect(find.text('Ways to pay off your debts'), findsOneWidget);
    expect(find.text('The avalanche method'), findsOneWidget);
    expect(
      find.text(
        "Best if you'll stick to a plan: it costs the least in interest.",
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Alternatives if you can borrow'),
      100,
    );
    expect(
      find.textContaining('These mean taking on new credit.'),
      findsOneWidget,
    );
  });

  testWidgets('a borrowing alternative is never marked cheapest', (
    tester,
  ) async {
    useTallScreen(tester);
    // The 5% consolidation loan costs least here (£9.25 interest), but the
    // badge goes to the cheapest way to pay off: highest interest first.
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a')],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plans,
    );
    await tester.scrollUntilVisible(find.text('Cheapest'), 100);
    final cheapestCard = find.ancestor(
      of: find.text('Cheapest'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(
        of: cheapestCard,
        matching: inCard('Highest interest first'),
      ),
      findsOneWidget,
    );
    expect(find.text('Cheapest'), findsOneWidget);
  });

  testWidgets('shows the card moves and their fees', (tester) async {
    useTallScreen(tester);
    await pumpApp(
      tester,
      debts: [store, amex],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plans,
    );
    await tester.scrollUntilVisible(find.text('1 move · £30.00 in fees'), 100);
    expect(find.text('1 move · £30.00 in fees'), findsOneWidget);
  });

  testWidgets('says when no card has an offer', (tester) async {
    useTallScreen(tester);
    await pumpApp(
      tester,
      debts: [store],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plans,
    );
    const reason =
        'No card has a balance transfer offer yet. Add one on a '
        "card's details.";
    await tester.scrollUntilVisible(find.text(reason), 100);
    expect(find.text(reason), findsOneWidget);
  });

  testWidgets('says when no move between your cards would save money', (
    tester,
  ) async {
    useTallScreen(tester);
    // 13% onto 12% with a 10% fee never pays for itself.
    await pumpApp(
      tester,
      debts: [
        testDebt(id: 'a', name: 'A', aprBps: 1300),
        testDebt(
          id: 'b',
          name: 'B',
          aprBps: 1200,
          transferOffer: const TransferOffer(
            feeBps: 1000,
            availableCredit: Money(500000, 'GBP'),
          ),
        ),
      ],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plans,
    );
    const reason = 'No move between your cards would save money.';
    await tester.scrollUntilVisible(find.text(reason), 100);
    expect(find.text(reason), findsOneWidget);
  });

  testWidgets('marks the card-transfers card cheapest when it wins', (
    tester,
  ) async {
    useTallScreen(tester);
    await pumpApp(
      tester,
      debts: [store, amex],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plans,
    );
    await tester.scrollUntilVisible(find.text('Cheapest'), 100);
    final cheapestCard = find.ancestor(
      of: find.text('Cheapest'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(
        of: cheapestCard,
        matching: inCard('Move balances between your cards'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('races the pay-off methods to zero', (tester) async {
    useTallScreen(tester);
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a')],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plans,
    );
    expect(find.text('Race to zero'), findsOneWidget);
    final chart = tester.widget<BalanceLineChart>(
      find.byType(BalanceLineChart).first,
    );
    // Highest interest first, smallest balance first, your order, and the
    // minimums-only line (dashed, last).
    expect(chart.lines, hasLength(4));
    expect(chart.lines.last.style, LineStyle.dashed);
    expect(chart.lines[1].style, isNot(chart.lines[0].style));
  });

  testWidgets('borrowing alternatives are collapsed until asked for', (
    tester,
  ) async {
    useTallScreen(tester);
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a')],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plans,
    );
    expect(find.text('Show alternatives'), findsOneWidget);
    expect(inCard('Consolidation loan'), findsNothing);
    await showAlternatives(tester);
    await tester.scrollUntilVisible(inCard('Consolidation loan'), 200);
    expect(inCard('Consolidation loan'), findsOneWidget);
  });

  testWidgets('the slider says what paying more changes', (tester) async {
    useTallScreen(tester);
    await pumpApp(
      tester,
      debts: [simple], // 1,000.00 at 0%
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.plans,
    );
    expect(find.textContaining('less interest'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('payMore')));
    await tester.pumpAndSettle();
    // 4 months at 250.00 becomes 3 at 375.00; no interest at 0%.
    expect(find.text('1 month sooner, £0.00 less interest'), findsOneWidget);
  });
}
