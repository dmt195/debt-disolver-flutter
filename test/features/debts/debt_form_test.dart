import 'package:debt_destroyer/app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  Finder field(String label) => find.widgetWithText(TextFormField, label);

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
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
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

  testWidgets('choosing Loan for a new debt turns off overpaying', (
    tester,
  ) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await tester.tap(find.text('Loan'));
    await tester.pumpAndSettle();
    await fill(tester);
    await save(tester);
    expect(app.repository.stored.single.type, DebtType.loan);
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
}
