import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/charts/balance_line_chart.dart';
import 'package:debt_destroyer/features/debts/presentation/debt_form_screen.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  final debts = [
    testDebt(id: 'od', name: 'Overdraft', aprBps: 3990),
    testDebt(id: 'car', name: 'Car loan', aprBps: 790),
  ];

  testWidgets('shows the debt-free date, the chart and this month', (
    tester,
  ) async {
    await pumpApp(tester, location: Routes.home, debts: debts);
    expect(find.text('Debt-free by'), findsOneWidget);
    expect(find.byType(BalanceLineChart), findsOneWidget);
    expect(find.text('Next up: Overdraft gone'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Pay this month'), 200);
    expect(find.text('Pay this month'), findsOneWidget);
    expect(find.text('Car loan'), findsOneWidget);
  });

  testWidgets('with no debts, invites the first one', (tester) async {
    await pumpApp(tester, location: Routes.home);
    await tester.tap(find.text('Add your first debt'));
    await tester.pumpAndSettle();
    expect(find.byType(DebtFormScreen), findsOneWidget);
  });

  testWidgets('a budget below the minimums shows the shortfall', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      location: Routes.home,
      debts: debts,
      settings: {SettingsKeys.monthlyBudgetMinor: 1000},
    );
    expect(find.byType(BalanceLineChart), findsNothing);
    await tester.tap(find.text('Change budget'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.settings);
  });

  testWidgets('tapping the chart opens the plan it follows', (tester) async {
    final app = await pumpApp(tester, location: Routes.home, debts: debts);
    await tester.tap(find.byType(BalanceLineChart));
    await tester.pumpAndSettle();
    expect(app.router.location, startsWith('${Routes.plans}/'));
  });

  testWidgets('large text does not overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, location: Routes.home, debts: debts);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the chart is labelled with the month at its right edge', (
    tester,
  ) async {
    // Minimums clear these, more slowly: the chart runs past debt-free.
    await pumpApp(
      tester,
      location: Routes.home,
      debts: [
        testDebt(id: 'a'),
        testDebt(id: 'b', aprBps: 990),
      ],
    );
    final chart = tester.widget<BalanceLineChart>(
      find.byType(BalanceLineChart).first,
    );
    expect(chart.lines, hasLength(2));
    final lastMonth = chart.lines
        .map((l) => l.values.length - 1)
        .reduce((a, b) => a > b ? a : b);
    // The fixed clock is 24 Sep 2026.
    expect(
      chart.endLabel,
      DateFormat.yMMM('en_GB').format(DateTime(2026, 9 + lastMonth)),
    );
  });

  testWidgets('the plan behind the chart is the one Home shows', (
    tester,
  ) async {
    useTallScreen(tester);
    final app = await pumpApp(
      tester,
      location: Routes.home,
      debts: [testDebt(id: 'a')], // 1,000.00 at 19.9%; default budget 300.00
      scenarios: [
        Scenario(
          id: 's1',
          name: 'Bonus',
          monthlyBudget: const Money(90000, 'GBP'),
          parameters: const StrategyParameters(),
          createdAt: DateTime(2026, 9),
        ),
      ],
    );
    // What-ifs on Plans must not change what Home's chart opens.
    app.container.read(selectedScenarioIdProvider.notifier).select('s1');
    app.container.read(extraPaymentProvider.notifier).set(10000);
    await tester.pumpAndSettle();
    final hero = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .firstWhere((d) => d != null && d.contains('\n'))!
        .replaceAll('\n', ' ');
    await tester.tap(find.byType(BalanceLineChart));
    await tester.pumpAndSettle();
    expect(find.textContaining('a month extra'), findsNothing);
    expect(find.textContaining('Scenario: Bonus'), findsNothing);
    // Home shows "Jan\n2027"; plan detail spells the month out.
    final detailDate = DateFormat.yMMMM('en_GB')
        .format(DateFormat.yMMM('en_GB').parse(hero));
    expect(find.text(detailDate), findsOneWidget);
  });
}
