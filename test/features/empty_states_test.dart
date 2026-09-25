import 'package:debt_destroyer/app/router.dart';
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
            theme: ThemeData(brightness: brightness),
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
}
