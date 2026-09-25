import 'package:debt_destroyer/app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../helpers/debts.dart';
import '../helpers/pump_app.dart';

const _hiVis = Color(0xFFFFC400);

/// Every painted text colour on screen, including nested spans, except the
/// bottom nav: its selected tab is hi-vis by design (spec §5.1).
List<Color?> _textColours(WidgetTester tester) {
  final colours = <Color?>[];
  final inNav = find
      .descendant(
        of: find.byType(NavigationBar),
        matching: find.byType(RichText),
      )
      .evaluate()
      .toSet();
  for (final e in find.byType(RichText).evaluate()) {
    if (inNav.contains(e)) continue;
    (e.widget as RichText).text.visitChildren((span) {
      colours.add(span.style?.color);
      return true;
    });
  }
  return colours;
}

void main() {
  testWidgets('hi-vis is never a text colour in dark mode', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    useTallScreen(tester);
    final app = await pumpApp(
      tester,
      debts: [
        testDebt(id: 'a', name: 'Visa'),
        testDebt(id: 'b', aprBps: 990),
      ],
    );
    for (final location in [
      Routes.home,
      Routes.debts,
      Routes.plans,
      Routes.plan(StrategyId.avalanche),
      Routes.scenarios,
    ]) {
      await app.router.go(tester, location);
      expect(_textColours(tester), isNot(contains(_hiVis)), reason: location);
    }
    // A focused field's floating label.
    await app.router.go(tester, Routes.newDebt);
    await tester.tap(find.byType(TextFormField).first);
    await tester.pumpAndSettle();
    expect(_textColours(tester), isNot(contains(_hiVis)), reason: 'form');
  });
}
