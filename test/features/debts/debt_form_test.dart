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
    final tile = find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('type-'),
      ),
    );
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    // Back to the top, where the other fields start.
    await tester.scrollUntilVisible(field('Name'), -100, scrollable: formList);
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

  testWidgets(
    'editing a loan saved with a percentage minimum, unchanged, keeps it',
    (tester) async {
      final app = await pumpApp(
        tester,
        // Defaults: minPaymentPercentBps 300, minPaymentFloor 2500.
        debts: [testDebt(id: 'a', type: DebtType.loan)],
        location: Routes.editDebt('a'),
      );
      await save(tester);
      final saved = app.repository.stored.single;
      expect(saved.minPaymentPercentBps, 300);
      expect(saved.minPaymentFloor.minor, 2500);
    },
  );

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
    // The form is longer than the screen: build the switch before tapping.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('promo')),
      100,
      scrollable: formList,
    );
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

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.scrollUntilVisible(
      find.byKey(ValueKey(key)),
      100,
      scrollable: formList,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String label, String text) async {
    await tester.scrollUntilVisible(field(label), 100, scrollable: formList);
    await tester.enterText(field(label), text);
  }

  testWidgets('records a balance transfer offer on a card', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester);
    await tapKey(tester, 'offer');
    await enter(tester, 'Transfer fee (%)', '3');
    await tapKey(tester, 'offerPromo');
    await enter(tester, 'Offer rate (APR %)', '0');
    await enter(tester, 'Offer length (months)', '12');
    await enter(tester, 'Available credit', '2000');
    await save(tester);
    expect(
      app.repository.stored.single.transferOffer,
      const TransferOffer(
        feeBps: 300,
        promo: Promo(aprBps: 0, months: 12),
        availableCredit: Money(200000, 'GBP'),
      ),
    );
  });

  testWidgets('loans have no offer section, and switching drops the offer', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      debts: [
        testDebt(
          id: 'a',
          transferOffer: const TransferOffer(
            feeBps: 300,
            availableCredit: Money(200000, 'GBP'),
          ),
        ),
      ],
      location: Routes.editDebt('a'),
    );
    await chooseType(tester, 'Loan');
    expect(find.byKey(const ValueKey('offer')), findsNothing);
    // The saved debt has a 3% minimum, so the loan keeps both minimum
    // fields (no single "Monthly payment" field); save as is.
    await save(tester);
    expect(app.repository.stored.single.transferOffer, isNull);
  });

  testWidgets('editing a card with an offer pre-fills its fields', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      debts: [
        testDebt(
          id: 'a',
          transferOffer: const TransferOffer(
            feeBps: 300,
            promo: Promo(aprBps: 0, months: 12),
            availableCredit: Money(200000, 'GBP'),
          ),
        ),
      ],
      location: Routes.editDebt('a'),
    );
    Future<void> expectValue(String label, String value) async {
      await tester.scrollUntilVisible(field(label), 100, scrollable: formList);
      expect(
        tester.widget<TextFormField>(field(label)).controller!.text,
        value,
      );
    }

    await expectValue('Transfer fee (%)', '3');
    await expectValue('Available credit', '2000');
    await expectValue('Offer rate (APR %)', '0');
    await expectValue('Offer length (months)', '12');

    // Saving unchanged keeps the same offer.
    await save(tester);
    expect(
      app.repository.stored.single.transferOffer,
      const TransferOffer(
        feeBps: 300,
        promo: Promo(aprBps: 0, months: 12),
        availableCredit: Money(200000, 'GBP'),
      ),
    );
  });

  testWidgets('explains an offer with no available credit', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester);
    await tapKey(tester, 'offer');
    await enter(tester, 'Transfer fee (%)', '3');
    await enter(tester, 'Available credit', '0');
    await save(tester);
    await tester.scrollUntilVisible(
      find.text('Enter the credit still available on this card'),
      100,
      scrollable: formList,
    );
    expect(
      find.text('Enter the credit still available on this card'),
      findsOneWidget,
    );
    expect(app.repository.stored, isEmpty);
  });

  testWidgets('fits a phone screen with the promo section open', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.reset);
    await pumpApp(tester, location: Routes.newDebt);
    // The form is longer than the screen: build the switch before tapping.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('promo')),
      100,
      scrollable: formList,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('promo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('promo')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('marking a debt paid off celebrates and clears it', (
    tester,
  ) async {
    useTallScreen(tester);
    final app = await pumpApp(
      tester,
      debts: [
        testDebt(id: 'a', name: 'Visa'),
        testDebt(id: 'b', name: 'Loan'),
      ],
      location: Routes.editDebt('a'),
    );
    await tester.tap(find.text('Mark as paid off'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.cleared('a'));
    expect(find.text('Visa demolished.'), findsOneWidget);
    expect([for (final d in await app.repository.loadAll('GBP')) d.id], ['b']);
  });

  testWidgets('a new debt has nothing to mark as paid off', (tester) async {
    await pumpApp(tester, location: Routes.newDebt);
    expect(find.text('Mark as paid off'), findsNothing);
  });

  group('kind-of-debt tiles', () {
    testWidgets('one tile per kind, the chosen one selected', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, location: Routes.newDebt);
      for (final t in DebtType.values) {
        expect(find.byKey(ValueKey('type-${t.name}')), findsOneWidget);
      }
      Object node(DebtType t) =>
          tester.getSemantics(find.byKey(ValueKey('type-${t.name}')));
      expect(node(DebtType.creditCard), isSemantics(isSelected: true));
      expect(node(DebtType.loan), isSemantics(isSelected: false));
      await chooseType(tester, 'Loan');
      expect(node(DebtType.loan), isSemantics(isSelected: true));
      expect(node(DebtType.creditCard), isSemantics(isSelected: false));
      handle.dispose();
    });

    testWidgets('four across on a phone, at least 48 tall', (tester) async {
      tester.view
        ..devicePixelRatio = 3
        ..physicalSize = const Size(390 * 3, 844 * 3);
      addTearDown(tester.view.reset);
      await pumpApp(tester, location: Routes.newDebt);
      Offset at(DebtType t) =>
          tester.getTopLeft(find.byKey(ValueKey('type-${t.name}')));
      expect(at(DebtType.overdraft).dy, at(DebtType.creditCard).dy);
      expect(
        at(DebtType.studentLoan).dy,
        greaterThan(at(DebtType.creditCard).dy),
      );
      for (final t in DebtType.values) {
        expect(
          tester.getSize(find.byKey(ValueKey('type-${t.name}'))).height,
          greaterThanOrEqualTo(48),
        );
      }
    });

    testWidgets('two across when narrow, and large text fits', (tester) async {
      tester.view
        ..devicePixelRatio = 3
        ..physicalSize = const Size(340 * 3, 844 * 3);
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester, location: Routes.newDebt);
      expect(tester.takeException(), isNull);
      Offset at(DebtType t) =>
          tester.getTopLeft(find.byKey(ValueKey('type-${t.name}')));
      expect(at(DebtType.storeCard).dy, at(DebtType.creditCard).dy);
      expect(at(DebtType.loan).dy, greaterThan(at(DebtType.creditCard).dy));
    });
  });
}
