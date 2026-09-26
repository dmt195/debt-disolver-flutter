import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/settings/presentation/parameter_fields.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  Finder field(String label) => find.widgetWithText(TextFormField, label);

  // Every text field's EditableText is itself a horizontal Scrollable, so
  // the vertical settings list has to be named explicitly to scroll it
  // unambiguously.
  final settingsList = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );

  Future<void> save(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'Save');
    // More fields than fit on screen now, so the button may not have been
    // built yet: scroll (rather than ensureVisible) to reach it.
    await tester.scrollUntilVisible(button, 100, scrollable: settingsList);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    // Scrolling to the button aligns it at the top, which can push earlier
    // fields (and their forced errors) out of the built range. Scroll back
    // so callers can find those without scrolling themselves.
    await tester.scrollUntilVisible(
      field('Monthly budget'),
      -100,
      scrollable: settingsList,
    );
  }

  // The list builds lazily, so fields low on the screen may not exist until
  // scrolled to.
  Future<void> enter(WidgetTester tester, String label, String text) async {
    await tester.scrollUntilVisible(
      field(label),
      100,
      scrollable: settingsList,
    );
    await tester.ensureVisible(field(label));
    await tester.pumpAndSettle();
    await tester.enterText(field(label), text);
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

  testWidgets('saves the loan term, fee and a credit limit', (tester) async {
    final app = await pumpApp(tester, location: Routes.settings);
    await enter(tester, 'Loan term (months)', '36');
    await enter(tester, 'Arrangement fee (% of loan)', '1.5');
    await enter(tester, 'Credit limit (optional)', '5,000');
    await save(tester);
    final p = app.container
        .read(settingsControllerProvider)
        .value!
        .strategyParameters;
    expect(p.consolidationTermMonths, 36);
    expect(p.consolidationFeeBps, 150);
    expect(p.transferCreditLimit, const Money(500000, 'GBP'));
  });

  testWidgets('an empty credit limit means none is set', (tester) async {
    final app = await pumpApp(
      tester,
      location: Routes.settings,
      settings: {SettingsKeys.transferCreditLimitMinor: 500000},
    );
    await tester.scrollUntilVisible(
      find.text('5000'),
      100,
      scrollable: settingsList,
    );
    expect(find.text('5000'), findsOneWidget);
    await enter(tester, 'Credit limit (optional)', '');
    await save(tester);
    expect(
      app.container
          .read(settingsControllerProvider)
          .value!
          .strategyParameters
          .transferCreditLimit,
      isNull,
    );
  });

  testWidgets('shows why a term or limit was rejected', (tester) async {
    await pumpApp(tester, location: Routes.settings);
    await enter(tester, 'Loan term (months)', '3');
    await enter(tester, 'Credit limit (optional)', '0');
    await save(tester);
    await tester.scrollUntilVisible(
      find.text('Enter between 6 and 120 months'),
      -100,
      scrollable: settingsList,
    );
    expect(find.text('Enter between 6 and 120 months'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Enter a limit above zero, or leave it empty'),
      100,
      scrollable: settingsList,
    );
    expect(
      find.text('Enter a limit above zero, or leave it empty'),
      findsOneWidget,
    );
  });

  testWidgets('the consolidation rate can be entered per month', (
    tester,
  ) async {
    final app = await pumpApp(tester, location: Routes.settings);
    final unit = find.byKey(
      ValueKey('${ParameterField.consolidationApr}-unit'),
    );
    await tester.scrollUntilVisible(unit, 100, scrollable: settingsList);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: unit, matching: find.text('a month')));
    await tester.pumpAndSettle();
    await enter(tester, 'Loan interest rate (% a month)', '0.5');
    await save(tester);
    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.strategyParameters.consolidationAprBps, 617);
  });
}
