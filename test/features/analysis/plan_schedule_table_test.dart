import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_schedule_table.dart';
import 'package:debt_destroyer/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  ScheduleTable table(int columns) => ScheduleTable(
    headers: ['Month', for (var i = 1; i < columns; i++) 'Column $i'],
    rows: [
      for (var m = 1; m <= 3; m++)
        ScheduleRow(
          month: m,
          amounts: [for (var i = 1; i < columns; i++) Money(1000 * m, 'GBP')],
        ),
    ],
  );

  Future<void> show(WidgetTester tester, ScheduleTable t) => tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 340, child: PlanScheduleTable(table: t)),
          ),
        ),
      ),
    ),
  );

  final right = find.byTooltip('Scroll right');
  final left = find.byTooltip('Scroll left');

  testWidgets('a wide table shows it scrolls sideways, and scrolls on tap', (
    tester,
  ) async {
    await show(tester, table(7)); // 64 + 6 × 132: much wider than 340
    await tester.pumpAndSettle();
    expect(right, findsOneWidget);
    expect(left, findsNothing);

    await tester.tap(right);
    await tester.pumpAndSettle();
    expect(left, findsOneWidget);

    // Keep going to the end: the right cue goes.
    for (var i = 0; i < 5 && tester.any(right); i++) {
      await tester.tap(right);
      await tester.pumpAndSettle();
    }
    expect(right, findsNothing);
    expect(left, findsOneWidget);
  });

  testWidgets('dragging updates the cues too', (tester) async {
    await show(tester, table(7));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Month'), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(right, findsNothing);
    expect(left, findsOneWidget);
  });

  testWidgets('a table that fits shows no cues', (tester) async {
    await show(tester, table(3)); // 64 + 2 × 132 = 328
    await tester.pumpAndSettle();
    expect(right, findsNothing);
    expect(left, findsNothing);
  });
}
