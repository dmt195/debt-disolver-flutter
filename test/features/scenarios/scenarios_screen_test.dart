import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/charts/comparison_bars.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  final bonus = Scenario(
    id: 's1',
    name: 'Bonus',
    monthlyBudget: const Money(50000, 'GBP'),
    parameters: const StrategyParameters(),
    createdAt: DateTime(2026, 9),
  );

  // Every text field's EditableText is itself a horizontal Scrollable, so
  // the vertical form list has to be named explicitly to scroll it
  // unambiguously.
  final formList = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );

  testWidgets('lists saved scenarios', (tester) async {
    await pumpApp(tester, scenarios: [bonus], location: Routes.scenarios);
    expect(find.text('Bonus'), findsOneWidget);
    expect(find.text('£500.00 a month'), findsOneWidget);
  });

  testWidgets('with none saved, explains how to make one', (tester) async {
    await pumpApp(tester, location: Routes.scenarios);
    expect(find.textContaining('No saved scenarios yet'), findsOneWidget);
  });

  testWidgets("edits a scenario's name and budget", (tester) async {
    final app = await pumpApp(
      tester,
      scenarios: [bonus],
      location: Routes.scenarios,
    );
    await tester.tap(find.text('Bonus'));
    await tester.pumpAndSettle();
    expect(find.text('Edit scenario'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Pay rise',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Monthly budget'),
      '650',
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Save'),
      100,
      scrollable: formList,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final saved = app.scenarios.stored.single;
    expect(saved.name, 'Pay rise');
    expect(saved.monthlyBudget, const Money(65000, 'GBP'));
    expect(app.router.location, Routes.scenarios);
  });

  testWidgets('an empty name is refused in the editor', (tester) async {
    final app = await pumpApp(
      tester,
      scenarios: [bonus],
      location: Routes.editScenario('s1'),
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), ' ');
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Save'),
      100,
      scrollable: formList,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    // Scrolling to the button pushed the Name field (and its forced error)
    // out of the built range; scroll back to see it.
    await tester.scrollUntilVisible(
      find.widgetWithText(TextFormField, 'Name'),
      -100,
      scrollable: formList,
    );
    expect(find.text('Enter a name'), findsOneWidget);
    expect(app.scenarios.stored.single.name, 'Bonus');
  });

  testWidgets('deletes a scenario after asking', (tester) async {
    final app = await pumpApp(
      tester,
      scenarios: [bonus],
      location: Routes.scenarios,
    );
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Bonus?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(app.scenarios.stored, isEmpty);
  });

  testWidgets('compares the best plan in each scenario', (tester) async {
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a')], // 1,000.00 at 19.9%, min 3% or 25.00
      scenarios: [bonus],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.scenarios,
    );
    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();
    // Borrowing alternatives are left out: the best pay-off method is
    // highest interest first in both.
    expect(
      find.text(
        'Highest interest first: debt-free in 4 months, £34.65 interest',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Highest interest first: debt-free in 3 months, £23.44 interest',
      ),
      findsOneWidget,
    );
    final cheapest = find.ancestor(
      of: find.text('Cheapest'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: cheapest, matching: find.text('Bonus')),
      findsOneWidget,
    );
  });

  testWidgets('compares scenarios as bars', (tester) async {
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a')],
      scenarios: [bonus],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.scenarios,
    );
    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();
    expect(find.text('Interest paid, best plan in each'), findsOneWidget);
    final bars = tester.widget<ComparisonBars>(find.byType(ComparisonBars));
    expect([for (final b in bars.bars) b.label], ['Current', 'Bonus']);
    expect([for (final b in bars.bars) b.highlight], [false, true]);
    expect(bars.bars.first.trailing, 'Jan 2027'); // 4 months from Sep 2026
  });
}
