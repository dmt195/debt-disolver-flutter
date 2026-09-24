import 'package:debt_destroyer/app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../helpers/pump_app.dart';

void main() {
  Finder field(String label) => find.widgetWithText(TextFormField, label);

  // Every text field's EditableText is itself a horizontal Scrollable, so
  // the vertical debt-form list has to be named explicitly to scroll it
  // unambiguously (see test/features/debts/debt_form_test.dart).
  final formList = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'add a promo debt, compare, pay more, save a scenario, open its plan',
    (tester) async {
      final app = await pumpApp(tester);

      await tapVisible(tester, find.text('Add debt'));
      await tester.enterText(field('Name'), 'Visa');
      await tester.enterText(field('Balance'), '2000');
      await tester.enterText(field('Interest rate (APR %)'), '22.9');
      await tester.enterText(field('Minimum payment (% of balance)'), '3');
      await tester.enterText(field('Minimum payment (at least)'), '25');
      await tapVisible(tester, find.byKey(const ValueKey('promo')));
      await tester.enterText(field('Promotional rate (APR %)'), '0');
      // More fields than fit on screen now the promo fields are showing, so
      // the button may not have been built yet: scroll rather than
      // ensureVisible to reach it.
      final saveDebt = find.widgetWithText(FilledButton, 'Save');
      await tester.scrollUntilVisible(saveDebt, 100, scrollable: formList);
      await tester.pumpAndSettle();
      await tester.tap(saveDebt);
      await tester.pumpAndSettle();
      expect(
        app.repository.stored.single.promo,
        const Promo(aprBps: 0, months: 12),
      );

      await tapVisible(tester, find.text('Compare strategies'));
      expect(app.router.location, Routes.strategies);
      expect(find.textContaining('Minimums only: '), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('payMore')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Save as scenario'));
      await tester.enterText(
        find.byKey(const ValueKey('scenarioName')),
        'Stretch',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(app.scenarios.stored.single.name, 'Stretch');
      // Default budget £300.00, plus the slider's centre tap: step £5 across
      // 60 divisions of the £300 budget, so a centre tap adds £150.00.
      expect(
        app.scenarios.stored.single.monthlyBudget,
        const Money(45000, 'GBP'),
      );

      await tester.scrollUntilVisible(find.text('Highest interest first'), 100);
      await tapVisible(tester, find.text('Highest interest first'));
      expect(app.router.location, Routes.plan(StrategyId.avalanche));
      expect(find.text('Scenario: Stretch'), findsOneWidget);
    },
  );
}
