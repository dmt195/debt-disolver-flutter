import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the current settings', (tester) async {
    await pumpApp(tester, location: Routes.settings);
    expect(find.text('GBP (£)'), findsOneWidget);
    expect(find.text('300'), findsOneWidget); // budget
    expect(find.text('5'), findsOneWidget); // consolidation APR
    expect(find.text('12'), findsOneWidget); // promo months
  });

  testWidgets('saves a new budget and strategy settings', (tester) async {
    final app = await pumpApp(tester, location: Routes.settings);
    await tester.enterText(field('Monthly budget'), '450.50');
    await tester.enterText(field('Interest-free months'), '18');
    await tester.enterText(field('Transfer fee (% of balance)'), '2.5');
    await save(tester);

    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.monthlyBudget, const Money(45050, 'GBP'));
    expect(settings.strategyParameters.promoMonths, 18);
    expect(settings.strategyParameters.transferFeeBps, 250);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('shows why a value was rejected', (tester) async {
    final app = await pumpApp(tester, location: Routes.settings);
    await tester.enterText(field('Monthly budget'), '0');
    await tester.enterText(field('Interest-free months'), '200');
    await save(tester);
    expect(find.text('Enter a budget above zero'), findsOneWidget);
    expect(find.text('Enter between 0 and 120 months'), findsOneWidget);
    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.monthlyBudget, const Money(30000, 'GBP'));
    expect(settings.strategyParameters.promoMonths, 12);
  });

  testWidgets('saving again without a fix keeps the message', (tester) async {
    await pumpApp(tester, location: Routes.settings);
    await tester.enterText(field('Monthly budget'), '0');
    await save(tester);
    await save(tester);
    expect(find.text('Enter a budget above zero'), findsOneWidget);
  });

  testWidgets('a corrected value saves on the next try', (tester) async {
    final app = await pumpApp(tester, location: Routes.settings);
    await tester.enterText(field('Monthly budget'), '0');
    await save(tester);
    expect(find.text('Enter a budget above zero'), findsOneWidget);

    await tester.enterText(field('Monthly budget'), '450');
    await save(tester);
    expect(find.text('Enter a budget above zero'), findsNothing);
    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.monthlyBudget, const Money(45000, 'GBP'));
  });

  testWidgets('switching currency keeps amounts at face value', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [testDebt(id: 'a', balance: 123456)],
      location: Routes.settings,
    );
    await tester.tap(find.text('GBP (£)'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('JPY (¥)'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('JPY (¥)').last);
    await tester.pumpAndSettle();

    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.currencyCode, 'JPY');
    expect(settings.monthlyBudget, const Money(300, 'JPY'));
    expect(find.text('300'), findsOneWidget);
    expect(app.repository.stored.single.balance.minor, 1235);
  });
}
