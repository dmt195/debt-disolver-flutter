import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/charts/segment_bar.dart';
import 'package:debt_destroyer/core/charts/share_donut.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_screen.dart';
import 'package:debt_destroyer/features/progress/domain/progress.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

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
      find.widgetWithText(FilledButton, 'See plans'),
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
    await tester.tap(find.text('See plans'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.plans);
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
    // The debt wasn't deleted, so it comes back.
    expect(find.text('Visa'), findsOneWidget);
    expect(find.text('£2,000.00'), findsWidgets);
  });

  testWidgets('marks a card that has a transfer offer', (tester) async {
    await pumpApp(
      tester,
      debts: [
        testDebt(
          id: 'a',
          name: 'Amex',
          transferOffer: const TransferOffer(
            feeBps: 300,
            availableCredit: Money(200000, 'GBP'),
          ),
        ),
      ],
    );
    expect(find.textContaining('Transfer offer'), findsOneWidget);
  });

  group('reorderedIds', () {
    test('moves one debt and keeps the rest in order', () {
      expect(reorderedIds(['a', 'b', 'c'], from: 2, to: 0), ['c', 'a', 'b']);
      expect(reorderedIds(['a', 'b', 'c'], from: 0, to: 2), ['b', 'c', 'a']);
    });

    test('keeps debts that are hidden while being deleted', () {
      expect(reorderedIds(['a', 'c'], from: 1, to: 0, hidden: ['b']), [
        'c',
        'a',
        'b',
      ]);
    });
  });

  testWidgets('summarises with a donut and the budget bar', (tester) async {
    await pumpApp(tester, debts: [card, loan]);
    expect(find.byType(ShareDonut), findsOneWidget);
    expect(find.byType(SegmentBar), findsOneWidget);
    // 300.00 budget less 210.00 of minimums.
    expect(find.text('£90.00 extra goes to work each month'), findsOneWidget);
  });

  testWidgets('each debt shows its rate band and when it clears', (
    tester,
  ) async {
    await pumpApp(tester, debts: [card, loan]);
    expect(find.text('Med'), findsOneWidget); // 19.9%
    expect(find.text('Low'), findsOneWidget); // 6.5%
    expect(find.text('clears 1st'), findsOneWidget);
    expect(find.text('clears 2nd'), findsOneWidget);
  });

  testWidgets('large text does not overflow the rows', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a', name: 'A very long debt name indeed')],
    );
    expect(tester.takeException(), isNull);
  });

  group('cleared debts', () {
    Future<AppHarness> withCleared(WidgetTester tester) async {
      useTallScreen(tester);
      final app = await pumpApp(tester, debts: [card, loan]);
      await app.progress.saveCheckIn(
        at: DateTime(2026, 9, 24), // the test clock: after the first start
        balances: {'a': card.balance, 'b': const Money(0, 'GBP')},
      );
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('are listed apart, collapsed', (tester) async {
      await withCleared(tester);
      expect(find.byType(DebtTile), findsOneWidget);
      expect(find.text('Cleared (1)'), findsOneWidget);
      await tester.tap(find.text('Cleared (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Car loan'), findsOneWidget);
      expect(find.text('Cleared 24 Sept 2026'), findsOneWidget);
    });

    testWidgets('can be reopened with a new balance', (tester) async {
      final app = await withCleared(tester);
      await tester.tap(find.text('Cleared (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reopen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '500');
      await tester.tap(find.widgetWithText(FilledButton, 'Reopen'));
      await tester.pumpAndSettle();
      expect(find.byType(DebtTile), findsNWidgets(2));
      expect(find.text('Cleared (1)'), findsNothing);
      final history = await app.progress.load('GBP');
      expect(
        (history.starts.last.reason, history.starts.last.debtName),
        (StartReason.debtAdded, 'Car loan'),
      );
    });

    testWidgets('can be deleted after asking', (tester) async {
      final app = await withCleared(tester);
      await tester.tap(find.text('Cleared (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Cleared (1)'), findsNothing);
      expect(await app.repository.watchCleared().first, isEmpty);
    });
  });
}
