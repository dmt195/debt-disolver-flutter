import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/illustrations/wrecking_ball.dart';
import 'package:debt_destroyer/core/text_sharer.dart';
import 'package:debt_destroyer/features/home/presentation/home_screen.dart';
import 'package:debt_destroyer/features/progress/presentation/progress_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

class _RecordingSharer implements TextSharer {
  final shared = <String>[];

  @override
  Future<void> share(String text) async => shared.add(text);
}

void main() {
  final visa = testDebt(id: 'visa', name: 'Visa');
  final store = testDebt(id: 'store', name: 'Store card', balance: 30000);
  final od = testDebt(id: 'od', name: 'Overdraft', balance: 20000);
  const zero = Money(0, 'GBP');

  Future<AppHarness> clear(
    WidgetTester tester,
    List<Debt> debts,
    Map<String, Money> balances, {
    _RecordingSharer? sharer,
  }) async {
    useTallScreen(tester);
    final app = await pumpApp(
      tester,
      location: Routes.home,
      debts: debts,
      overrides: [
        if (sharer != null) textSharerProvider.overrideWithValue(sharer),
      ],
    );
    final outcome = await app.container
        .read(progressControllerProvider.notifier)
        .saveCheckIn(balances);
    await app.router.go(tester, Routes.cleared(outcome.cleared.first.debtId));
    return app;
  }

  testWidgets('each cleared debt gets its moment, then Home', (tester) async {
    final app = await clear(
      tester,
      [visa, store, od],
      {'visa': visa.balance, 'store': zero, 'od': zero},
    );
    expect(find.text('Store card demolished.'), findsOneWidget);
    expect(find.text("That's £300.00 gone for good."), findsOneWidget);
    expect(find.text('1 of 3 debts down'), findsOneWidget);
    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();
    expect(find.text('Overdraft demolished.'), findsOneWidget);
    expect(find.text('2 of 3 debts down'), findsOneWidget);
    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.home);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('the last debt ends on debt free', (tester) async {
    final app = await clear(tester, [store], {'store': zero});
    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.debtFree);
    expect(find.text('Debt free!'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.home);
  });

  testWidgets('sharing says what was cleared', (tester) async {
    final sharer = _RecordingSharer();
    await clear(
      tester,
      [visa, store],
      {'visa': visa.balance, 'store': zero},
      sharer: sharer,
    );
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(sharer.shared.single, contains('Store card'));
    expect(sharer.shared.single, contains('£300.00'));
  });

  testWidgets('opened with nothing to celebrate, it goes Home', (tester) async {
    final app = await pumpApp(tester, location: Routes.cleared('nope'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.home);
  });

  group('motion', () {
    // Opens the celebration without letting its animation finish.
    Future<AppHarness> openRaw(WidgetTester tester) async {
      useTallScreen(tester);
      final app = await pumpApp(
        tester,
        location: Routes.home,
        debts: [visa, store],
      );
      await app.container.read(progressControllerProvider.notifier).saveCheckIn(
        {'visa': visa.balance, 'store': zero},
      );
      app.container.read(routerProvider).go(Routes.cleared('store'));
      await tester.pump();
      await tester.pump();
      return app;
    }

    double scene(WidgetTester tester) => tester
        .widget<WreckingBallScene>(find.byType(WreckingBallScene))
        .progress;
    double headline(WidgetTester tester) =>
        tester.widget<Opacity>(find.byKey(const ValueKey('headline'))).opacity;

    void reduceMotion(WidgetTester tester) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }

    testWidgets('the ball swings once, then the headline slams in', (
      tester,
    ) async {
      await openRaw(tester);
      expect(scene(tester), lessThan(0.2));
      expect(headline(tester), 0);
      expect(find.text('Keep going'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(scene(tester), 1);
      expect(headline(tester), 1);
    });

    testWidgets('with reduced motion, the last frame at once', (tester) async {
      reduceMotion(tester);
      await openRaw(tester);
      expect(scene(tester), 1);
      expect(headline(tester), 1);
    });

    testWidgets('a rebuild does not replay it', (tester) async {
      await openRaw(tester);
      await tester.pumpAndSettle();
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(scene(tester), 1);
      expect(headline(tester), 1);
    });

    testWidgets('debt free raises the flag', (tester) async {
      final app = await clear(tester, [store], {'store': zero});
      app.container.read(routerProvider).go(Routes.debtFree);
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<DebtFreeScene>(find.byType(DebtFreeScene)).progress,
        lessThan(0.2),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<DebtFreeScene>(find.byType(DebtFreeScene)).progress,
        1,
      );
    });

    testWidgets('paints every frame', (tester) async {
      for (final brightness in Brightness.values) {
        for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildTheme(brightness),
              home: Column(
                children: [
                  SizedBox(width: 300, child: WreckingBallScene(progress: t)),
                  SizedBox(width: 300, child: DebtFreeScene(progress: t)),
                ],
              ),
            ),
          );
          expect(tester.takeException(), isNull);
        }
      }
    });
  });
}
