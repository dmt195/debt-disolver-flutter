import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/charts/balance_line_chart.dart';
import 'package:debt_destroyer/features/debts/presentation/debt_form_screen.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
