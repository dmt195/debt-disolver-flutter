import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/illustrations/illustration.dart';
import 'package:debt_destroyer/core/illustrations/kit.dart';
import 'package:debt_destroyer/core/illustrations/scenes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../helpers/debts.dart';
import '../helpers/pump_app.dart';

void main() {
  testWidgets('Home with no debts shows the empty lot', (tester) async {
    await pumpApp(tester, location: Routes.home);
    expect(find.byType(EmptyLot), findsOneWidget);
  });

  testWidgets('Debts with none shows the empty lot', (tester) async {
    await pumpApp(tester);
    expect(find.byType(EmptyLot), findsOneWidget);
  });

  testWidgets('Plans with no debts shows the empty lot', (tester) async {
    await pumpApp(tester, location: Routes.plans);
    expect(find.byType(EmptyLot), findsOneWidget);
  });

  testWidgets('no saved scenarios shows the signpost', (tester) async {
    await pumpApp(
      tester,
      location: Routes.scenarios,
      debts: [testDebt(id: 'a')],
    );
    expect(find.byType(Signpost), findsOneWidget);
  });

  testWidgets('every debt cleared shows the cleared plot', (tester) async {
    final app = await pumpApp(
      tester,
      location: Routes.home,
      debts: [testDebt(id: 'a')],
    );
    app.repository.applyCheckIn({
      'a': const Money(0, 'GBP'),
    }, DateTime(2026, 9, 24));
    await tester.pumpAndSettle();
    expect(find.byType(ClearedPlot), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    for (final progress in [0.0, 0.5, 1.0]) {
      testWidgets('scenes paint at $progress in ${brightness.name}', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(brightness),
            home: ListView(
              children: [
                const EmptyLot(),
                const Signpost(),
                ClimbWall(percent: 40, progress: progress),
                const ClearedPlot(),
              ],
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final (brightness, ink, brick) in [
    (Brightness.light, DestroyerColors.light.ink, DestroyerColors.light.track),
    (Brightness.dark, DestroyerColors.dark.ink, DestroyerColors.dark.track),
  ]) {
    testWidgets('scenes on the ground draw in ${brightness.name} ink', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(brightness),
          home: ListView(
            children: const [
              EmptyLot(),
              Signpost(),
              ClimbWall(percent: 40),
              ClearedPlot(),
            ],
          ),
        ),
      );
      final painters = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(Illustration),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((p) => p.painter);
      expect(painters, hasLength(4));
      for (final p in painters) {
        final painter = p! as InkPainter;
        expect(painter.ink, ink);
        // Bricks filled from the theme too: light bricks with light
        // outlines were a white blob in dark mode.
        expect(painter.brick, brick);
      }
    });
  }

  group('the check-in flag', () {
    test('stands on the top brick at the left, or on the ground', () {
      // The wall's top row is at y 31; each row is 13 lower.
      expect(climbFlagBase(0), const Offset(13, 31));
      expect(climbFlagBase(18).dy, 31); // 5 bricks gone: (0,0) still there
      expect(climbFlagBase(20).dy, 44); // 6 gone: the top row is empty
      expect(climbFlagBase(100).dy, 96); // no wall left: the ground
    });
  });
}
