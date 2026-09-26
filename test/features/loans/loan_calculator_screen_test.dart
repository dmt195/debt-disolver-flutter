import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/charts/balance_line_chart.dart';
import 'package:debt_destroyer/core/charts/draw_in.dart';
import 'package:debt_destroyer/features/ads/presentation/ad_banner.dart';
import 'package:debt_destroyer/features/debts/presentation/debt_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  Future<AppHarness> open(WidgetTester tester) {
    useTallScreen(tester);
    return pumpApp(tester, location: Routes.loanCalculator);
  }

  // The inputs sit below the answer: build each before typing.
  Future<void> type(WidgetTester tester, String key, String text) async {
    final field = find.byKey(ValueKey(key));
    await tester.scrollUntilVisible(
      field,
      100,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    await tester.enterText(field, text);
    await tester.pumpAndSettle();
  }

  Future<void> workOut(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('unknown')),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inHero(String text) => find.descendant(
    of: find.byKey(const ValueKey('hero')),
    matching: find.text(text),
  );

  Future<void> paymentCase(WidgetTester tester) async {
    await type(tester, 'calcAmount', '10000');
    await type(tester, 'calcRate', '12.9');
    await type(tester, 'calcTerm', '5');
  }

  testWidgets('opens from Plans, with no ad', (tester) async {
    final app = await pumpApp(
      tester,
      location: Routes.plans,
      debts: [testDebt(id: 'a')],
    );
    await tester.tap(find.byTooltip('Loan calculator'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.loanCalculator);
    expect(find.byType(AdBanner), findsNothing);
  });

  testWidgets('works out the payment', (tester) async {
    await open(tester);
    await paymentCase(tester);
    expect(inHero('£223.43'), findsOneWidget);
    expect(inHero('a month'), findsOneWidget);
    expect(find.text('£3,405.70'), findsOneWidget);
    expect(find.text('£13,405.70'), findsOneWidget);
    expect(find.byType(BalanceLineChart), findsOneWidget);
  });

  testWidgets('works out the term', (tester) async {
    await open(tester);
    await workOut(tester, 'Term');
    await type(tester, 'calcAmount', '10000');
    await type(tester, 'calcRate', '12.9');
    await type(tester, 'calcPayment', '300');
    expect(inHero('3 years 5 months'), findsOneWidget);
  });

  testWidgets('works out the amount', (tester) async {
    await open(tester);
    await workOut(tester, 'Amount');
    await type(tester, 'calcRate', '7.9');
    await type(tester, 'calcTerm', '4');
    await type(tester, 'calcPayment', '250');
    expect(inHero('£10,314.00'), findsOneWidget);
  });

  testWidgets('works out the rate', (tester) async {
    await open(tester);
    await workOut(tester, 'Rate');
    await type(tester, 'calcAmount', '10000');
    await type(tester, 'calcTerm', '5');
    await type(tester, 'calcPayment', '223.43');
    expect(inHero('12.9%'), findsOneWidget);
  });

  testWidgets('switching the unknown keeps the other figures', (tester) async {
    await open(tester);
    await paymentCase(tester);
    await workOut(tester, 'Term');
    await type(tester, 'calcPayment', '300');
    String text(String key) => tester
        .widget<TextFormField>(find.byKey(ValueKey(key)))
        .controller!
        .text;
    expect(text('calcAmount'), '10000');
    expect(text('calcRate'), '12.9');
    expect(inHero('3 years 5 months'), findsOneWidget);
  });

  testWidgets('asks for the missing figures', (tester) async {
    await open(tester);
    await type(tester, 'calcAmount', '10000');
    expect(
      inHero('Fill in the other three to see the answer.'),
      findsOneWidget,
    );
    final add = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add as a debt'),
    );
    expect(add.onPressed, isNull);
  });

  testWidgets("says when it can't be done", (tester) async {
    await open(tester);
    await workOut(tester, 'Term');
    await type(tester, 'calcAmount', '1200');
    await type(tester, 'calcRate', '12');
    await type(tester, 'calcPayment', '11.39');
    expect(
      inHero('This payment never clears the balance at this rate.'),
      findsOneWidget,
    );
    expect(find.byType(BalanceLineChart), findsNothing);
  });

  testWidgets("typing doesn't replay the chart", (tester) async {
    await open(tester);
    await paymentCase(tester);
    double factor() =>
        (tester
                    .widget<ClipRect>(
                      find.descendant(
                        of: find.byType(DrawIn),
                        matching: find.byType(ClipRect),
                      ),
                    )
                    .clipper!
                as RevealClipper)
            .factor;
    expect(factor(), 1);
    await tester.enterText(find.byKey(const ValueKey('calcTerm')), '4');
    await tester.pump();
    expect(factor(), 1);
  });

  testWidgets('add as a debt opens the form filled in', (tester) async {
    final app = await open(tester);
    await paymentCase(tester);
    final add = find.widgetWithText(FilledButton, 'Add as a debt');
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.byType(DebtFormScreen), findsOneWidget);
    String text(String label) => tester
        .widget<TextFormField>(find.widgetWithText(TextFormField, label))
        .controller!
        .text;
    expect(text('Balance'), '10000');
    expect(text('Interest rate (APR %)'), '12.9');
    expect(text('Monthly payment'), '223.43');
    expect(app.repository.stored, isEmpty);
  });

  testWidgets('large text fits a small phone', (tester) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(360 * 3, 740 * 3);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, location: Routes.loanCalculator);
    await paymentCase(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at large text the choices keep whole words', (tester) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(360 * 3, 740 * 3);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, location: Routes.loanCalculator);
    for (final label in ['Payment', 'Amount', 'Rate', 'Term']) {
      final text = find.descendant(
        of: find.byKey(const ValueKey('unknown')),
        matching: find.text(label),
      );
      // One line of 14pt text at 2×: well under two lines' height.
      expect(tester.getSize(text).height, lessThan(45), reason: label);
    }
  });

  testWidgets('a big answer stays on one line', (tester) async {
    await open(tester);
    await workOut(tester, 'Amount');
    await type(tester, 'calcRate', '5');
    await type(tester, 'calcTerm', '25');
    await type(tester, 'calcPayment', '9000');
    final figure = find
        .descendant(
          of: find.byKey(const ValueKey('hero')),
          matching: find.byType(Text),
        )
        .first;
    expect(tester.widget<Text>(figure).data, startsWith('£1,'));
    // One line of the 44pt figure.
    expect(tester.getSize(figure).height, lessThan(60));
  });

  testWidgets('the answer is announced as it changes', (tester) async {
    await open(tester);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('hero')),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.liveRegion ?? false),
        ),
      ),
      findsOneWidget,
    );
  });
}
