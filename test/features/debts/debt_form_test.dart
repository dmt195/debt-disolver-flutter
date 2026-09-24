import 'package:debt_destroyer/app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  Finder field(String label) => find.widgetWithText(TextFormField, label);

  // Every text field's EditableText is itself a horizontal Scrollable, so
  // the vertical form list has to be named explicitly to scroll it
  // unambiguously.
  final formList = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );

  Future<void> fill(
    WidgetTester tester, {
    String name = 'Visa',
    String balance = '1,234.56',
    String apr = '19.9',
    String minPercent = '3',
    String minFloor = '25',
  }) async {
    await tester.enterText(field('Name'), name);
    await tester.enterText(field('Balance'), balance);
    await tester.enterText(field('Interest rate (APR %)'), apr);
    await tester.enterText(field('Minimum payment (% of balance)'), minPercent);
    await tester.enterText(field('Minimum payment (at least)'), minFloor);
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'Save');
    // More fields than fit on screen now, so the button may not have been
    // built yet: scroll (rather than ensureVisible) to reach it.
    await tester.scrollUntilVisible(button, 100, scrollable: formList);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    // Scrolling to the button can push earlier fields (and their forced
    // errors) out of the built range. Scroll back so callers can find them
    // without scrolling themselves, unless saving succeeded and the form
    // navigated away (in which case the button itself is gone too).
    if (tester.any(button)) {
      await tester.scrollUntilVisible(
        field('Name'),
        -100,
        scrollable: formList,
      );
    }
  }

  Future<void> chooseType(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('adds a debt with exactly the amounts typed', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester);
    await save(tester);

    final saved = app.repository.stored.single;
    expect(saved.name, 'Visa');
    expect(saved.type, DebtType.creditCard);
    expect(saved.balance.minor, 123456);
    expect(saved.aprBps, 1990);
    expect(saved.minPaymentPercentBps, 300);
    expect(saved.minPaymentFloor.minor, 2500);
    expect(saved.allowsOverpayment, isTrue);
    expect(saved.promo, isNull);
    expect(app.router.location, Routes.debts);
  });

  testWidgets('optional minimums may be left empty', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester, minPercent: '', minFloor: '');
    await save(tester);
    final saved = app.repository.stored.single;
    expect(saved.minPaymentPercentBps, 0);
    expect(saved.minPaymentFloor.minor, 0);
  });

  testWidgets('rejects text that is not an amount', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester, balance: 'lots');
    await save(tester);
    expect(find.text('Enter an amount, e.g. 1234'), findsOneWidget);
    expect(app.repository.stored, isEmpty);
  });

  testWidgets('shows the rule each invalid value breaks', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester, name: '  ', balance: '0', apr: '150');
    await save(tester);
    expect(find.text('Enter a name'), findsOneWidget);
    expect(find.text('Enter a balance above zero'), findsOneWidget);
    expect(find.text('Enter a rate between 0 and 100'), findsOneWidget);
    expect(app.repository.stored, isEmpty);
  });

  testWidgets('saving again without a fix keeps the message', (tester) async {
    await pumpApp(tester, location: Routes.newDebt);
    await fill(tester, apr: '150');
    await save(tester);
    await save(tester);
    expect(find.text('Enter a rate between 0 and 100'), findsOneWidget);
  });

  testWidgets('a corrected debt saves on the next try', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester, apr: '150');
    await save(tester);
    expect(find.text('Enter a rate between 0 and 100'), findsOneWidget);

    await tester.enterText(field('Interest rate (APR %)'), '15');
    await save(tester);
    expect(app.repository.stored.single.aprBps, 1500);
  });

  testWidgets('offers every kind of debt', (tester) async {
    await pumpApp(tester, location: Routes.newDebt);
    await tester.tap(find.byKey(const ValueKey('type')));
    await tester.pumpAndSettle();
    for (final label in [
      'Credit card',
      'Store card or buy now, pay later',
      'Loan',
      'Overdraft',
      'Student loan',
      'Mortgage',
      'Friends & family',
      'Other',
    ]) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('choosing Student loan for a new debt turns off overpaying', (
    tester,
  ) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await chooseType(tester, 'Student loan');
    await fill(tester);
    await save(tester);
    expect(app.repository.stored.single.type, DebtType.studentLoan);
    expect(app.repository.stored.single.allowsOverpayment, isFalse);
  });

  testWidgets('edits an existing debt in place', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [testDebt(id: 'a', name: 'Visa', balance: 123456)],
      location: Routes.editDebt('a'),
    );
    expect(find.text('1234.56'), findsOneWidget);
    expect(find.text('19.9'), findsOneWidget);
    await tester.enterText(field('Name'), 'Visa Gold');
    await save(tester);
    final saved = app.repository.stored.single;
    expect(saved.id, 'a');
    expect(saved.name, 'Visa Gold');
    expect(saved.balance.minor, 123456);
  });

  testWidgets('refuses a debt beyond the maximum count', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [for (var i = 0; i < kMaxDebts; i++) testDebt(id: 'd$i')],
      location: Routes.newDebt,
    );
    await fill(tester);
    await save(tester);
    expect(find.text('You can track up to 50 debts'), findsOneWidget);
    expect(app.repository.stored, hasLength(kMaxDebts));
  });

  testWidgets('editing a debt that no longer exists shows an error', (
    tester,
  ) async {
    await pumpApp(tester, location: Routes.editDebt('gone'));
    expect(find.text('Edit debt'), findsOneWidget);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('a loan asks for one monthly payment', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await chooseType(tester, 'Loan');
    expect(field('Minimum payment (% of balance)'), findsNothing);
    await tester.enterText(field('Name'), 'Car');
    await tester.enterText(field('Balance'), '3000');
    await tester.enterText(field('Interest rate (APR %)'), '6.5');
    await tester.enterText(field('Monthly payment'), '150');
    await save(tester);
    final saved = app.repository.stored.single;
    expect(saved.minPaymentPercentBps, 0);
    expect(saved.minPaymentFloor.minor, 15000);
    expect(saved.allowsOverpayment, isTrue);
  });

  testWidgets('a loan saved with a percentage keeps both minimum fields', (
    tester,
  ) async {
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a', type: DebtType.loan)],
      location: Routes.editDebt('a'),
    );
    expect(field('Minimum payment (% of balance)'), findsOneWidget);
    expect(field('Minimum payment (at least)'), findsOneWidget);
  });

  testWidgets('explains minimums only for a student loan', (tester) async {
    await pumpApp(tester, location: Routes.newDebt);
    await chooseType(tester, 'Student loan');
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('minimumsOnly')),
    );
    expect(toggle.value, isTrue);
    expect(find.textContaining('written off'), findsOneWidget);
  });

  Future<void> turnOnPromo(WidgetTester tester, String rate) async {
    await tester.ensureVisible(find.byKey(const ValueKey('promo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('promo')));
    await tester.pumpAndSettle();
    await tester.enterText(field('Promotional rate (APR %)'), rate);
  }

  testWidgets('saves a promotional rate until a chosen month', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester);
    await turnOnPromo(tester, '0');
    await tester.ensureVisible(find.byKey(const ValueKey('promoUntil')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('promoUntil')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('March 2027').last);
    await tester.pumpAndSettle();
    await save(tester);
    // The test clock is 24 Sep 2026: September to March is 7 months.
    expect(
      app.repository.stored.single.promo,
      const Promo(aprBps: 0, months: 7),
    );
  });

  testWidgets("shows an existing promo's end month", (tester) async {
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a', promo: const Promo(aprBps: 0, months: 7))],
      location: Routes.editDebt('a'),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('promoUntil')),
      200,
      scrollable: formList,
    );
    expect(find.text('March 2027'), findsOneWidget);
  });

  testWidgets('rejects a promotional rate over 100%', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester);
    await turnOnPromo(tester, '150');
    await save(tester);
    // save() scrolls back to the top fields after saving; this error is
    // further down, on the promo rate field.
    await tester.scrollUntilVisible(
      field('Promotional rate (APR %)'),
      100,
      scrollable: formList,
    );
    expect(find.text('Enter a rate between 0 and 100'), findsOneWidget);
    expect(app.repository.stored, isEmpty);
  });
}
