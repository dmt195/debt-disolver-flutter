import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  final card = testDebt(id: 'a', name: 'Visa', balance: 200000);
  final loan = testDebt(
    id: 'b',
    name: 'Car loan',
    balance: 300000,
    aprBps: 650,
    minPaymentPercentBps: 0,
    minPaymentFloor: 15000,
    allowsOverpayment: false,
  );

  testWidgets('lists debts with the totals', (tester) async {
    await pumpApp(tester, debts: [card, loan]);
    expect(find.text('Visa'), findsOneWidget);
    expect(find.text('Car loan'), findsOneWidget);
    expect(find.text('£2,000.00'), findsOneWidget);
    expect(find.text('£5,000.00'), findsOneWidget); // total debt
    expect(find.text('£210.00'), findsOneWidget); // 60.00 + 150.00 minimums
    expect(find.text('£300.00'), findsOneWidget); // budget
    expect(find.textContaining('19.9% APR'), findsOneWidget);
  });

  testWidgets('with no debts, explains and disables comparing', (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('No debts yet'), findsOneWidget);
    final compare = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Compare strategies'),
    );
    expect(compare.onPressed, isNull);
  });

  testWidgets('warns when the budget is below the minimum payments', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      debts: [card, loan],
      settings: {SettingsKeys.monthlyBudgetMinor: 20000},
    );
    expect(
      find.text(
        "Your budget is £10.00 short of this month's minimum payments.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Change budget'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.settings);
  });

  testWidgets('compare opens the strategies', (tester) async {
    final app = await pumpApp(tester, debts: [card]);
    await tester.tap(find.text('Compare strategies'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.strategies);
  });

  testWidgets('tapping a debt opens it for editing', (tester) async {
    final app = await pumpApp(tester, debts: [card]);
    await tester.tap(find.text('Visa'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.editDebt('a'));
  });

  testWidgets('swiping asks before deleting', (tester) async {
    final app = await pumpApp(tester, debts: [card, loan]);

    await tester.drag(find.text('Visa'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete Visa?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(app.repository.stored, hasLength(2));

    await tester.drag(find.text('Visa'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(app.repository.stored.map((d) => d.id), ['b']);
    expect(find.text('Visa'), findsNothing);
  });

  testWidgets('a failed delete tells the user', (tester) async {
    final app = await pumpApp(tester, debts: [card]);
    app.repository.failWritesWith = Exception('disk full');
    await tester.drag(find.text('Visa'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't save your changes. Please try again."),
      findsOneWidget,
    );
  });
}
