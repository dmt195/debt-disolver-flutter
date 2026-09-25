import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/illustrations/scenes.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/progress/domain/progress_math.dart';
import 'package:debt_destroyer/features/progress/presentation/check_in_result_screen.dart';
import 'package:debt_destroyer/features/strategies/presentation/current_plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  final visa = testDebt(id: 'visa', name: 'Visa', aprBps: 2490);
  final loan = testDebt(id: 'loan', name: 'Loan', aprBps: 790, balance: 50000);
  Finder field(String id) => find.byKey(ValueKey('checkIn-$id'));
  String textOf(WidgetTester tester, String id) =>
      tester.widget<TextFormField>(field(id)).controller!.text;
  String input(int minor) => formatAmountInput(Money(minor, 'GBP'), 'en_GB');

  Future<AppHarness> open(
    WidgetTester tester, {
    DateTime Function()? now,
  }) async {
    useTallScreen(tester);
    final app = await pumpApp(
      tester,
      location: Routes.home,
      debts: [visa, loan],
      clock: now,
    );
    await app.router.go(tester, Routes.checkIn);
    return app;
  }

  testWidgets("right after the start, it fills in today's balances", (
    tester,
  ) async {
    await open(tester);
    expect(textOf(tester, 'visa'), input(100000));
    expect(textOf(tester, 'loan'), input(50000));
  });

  testWidgets('a month later, it fills in what the plan expected', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 24);
    final app = await open(tester, now: () => now);
    await app.router.go(tester, Routes.home);
    now = DateTime(2026, 10, 24);
    await app.router.go(tester, Routes.checkIn);
    final home =
        await app.container.read(homePlanProvider.future) as HomeFollowing;
    final debts = await app.container.read(debtsProvider.future);
    final expected = expectedBalances(home.result.plan, 1, debts);
    expect(textOf(tester, 'visa'), input(expected['visa']!.minor));
    expect(expected['visa']!.minor, lessThan(100000));
  });

  testWidgets('zero marks a debt paid off; more marks it as gone up', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(field('loan'), '0');
    await tester.enterText(field('visa'), '1,050');
    await tester.pump();
    expect(find.text('Paid off!'), findsOneWidget);
    expect(find.textContaining('£50.00 more than expected'), findsOneWidget);
  });

  testWidgets('saving records it and shows where you stand', (tester) async {
    final app = await open(tester);
    await tester.enterText(field('visa'), '600');
    await tester.tap(find.text('Save check-in'));
    await tester.pumpAndSettle();
    final history = await app.progress.load('GBP');
    expect(history.checkIns.last.balances['visa']!.balance.minor, 60000);
    expect(find.text('ahead of plan'), findsOneWidget);
    expect(app.router.location, Routes.checkInResult);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.home);
  });

  testWidgets('a balance that went up is noted on the result', (tester) async {
    await open(tester);
    await tester.enterText(field('visa'), '1,030');
    await tester.tap(find.text('Save check-in'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Visa went up £30.00'), findsOneWidget);
  });

  testWidgets('nonsense is refused and nothing is saved', (tester) async {
    final app = await open(tester);
    final before = (await app.progress.load('GBP')).checkIns.length;
    await tester.enterText(field('visa'), 'lots');
    await tester.tap(find.text('Save check-in'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.checkIn);
    expect((await app.progress.load('GBP')).checkIns, hasLength(before));
  });

  testWidgets('closing saves nothing', (tester) async {
    final app = await open(tester);
    final before = (await app.progress.load('GBP')).checkIns.length;
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect((await app.progress.load('GBP')).checkIns, hasLength(before));
  });

  testWidgets('clearing a debt leads on to its celebration', (tester) async {
    final app = await open(tester);
    await tester.enterText(field('loan'), '0');
    await tester.tap(find.text('Save check-in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue: 1 debt demolished'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.cleared('loan'));
  });

  testWidgets('a debt added meanwhile keeps what was typed', (tester) async {
    final app = await open(tester);
    await tester.enterText(field('visa'), '600');
    await app.repository.add(testDebt(id: 'amex', name: 'Amex', balance: 7000));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'visa'), '600');
    expect(textOf(tester, 'amex'), input(7000));
  });

  group('the result', () {
    // £30 more than the plan expected: behind, by an amount.
    Future<void> saveAndReachResult(WidgetTester tester) async {
      await tester.enterText(field('visa'), '1,030');
      await tester.tap(find.text('Save check-in'));
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (tester.any(find.byType(CheckInResultScreen))) return;
      }
    }

    testWidgets('counts the amount up, with the wall losing bricks', (
      tester,
    ) async {
      await open(tester);
      await saveAndReachResult(tester);
      expect(find.byType(ClimbWall), findsOneWidget);
      expect(find.text('£30.00'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('£30.00'), findsOneWidget);
      expect(tester.widget<ClimbWall>(find.byType(ClimbWall)).progress, 1);
    });

    testWidgets('with reduced motion, shows the amount at once', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await open(tester);
      await saveAndReachResult(tester);
      // One frame for the new history to load, then no animation.
      await tester.pump();
      expect(find.text('£30.00'), findsOneWidget);
      expect(tester.widget<ClimbWall>(find.byType(ClimbWall)).progress, 1);
    });
  });
}
