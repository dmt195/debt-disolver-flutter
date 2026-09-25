import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/charts/balance_line_chart.dart';
import 'package:debt_destroyer/core/charts/comparison_bars.dart';
import 'package:debt_destroyer/core/charts/segment_bar.dart';
import 'package:debt_destroyer/core/charts/share_donut.dart';
import 'package:debt_destroyer/core/charts/stacked_balance_chart.dart';
import 'package:debt_destroyer/core/widgets/outlined_card.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.light),
  home: Scaffold(
    body: Center(child: SizedBox(width: 340, child: child)),
  ),
);

void main() {
  testWidgets('line chart draws each line with its style and a label', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const BalanceLineChart(
          semanticLabel: 'Two plans',
          lines: [
            ChartLine(values: [10, 5, 0], color: Colors.blue),
            ChartLine(
              values: [10, 8, 6, 4],
              color: Colors.grey,
              style: LineStyle.dashed,
            ),
          ],
        ),
      ),
    );
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData, hasLength(2));
    // The first line is painted last, so it sits on top where lines overlap.
    expect(chart.data.lineBarsData.last.dashArray, isNull);
    expect(chart.data.lineBarsData.first.dashArray, isNotNull);
    // Monthly steps are drawn straight: smoothing makes them wobble.
    expect(chart.data.lineBarsData.every((l) => !l.isCurved), isTrue);
    expect(find.bySemanticsLabel('Two plans'), findsOneWidget);
  });

  testWidgets('a single-value line still draws two points', (tester) async {
    await tester.pumpWidget(
      host(
        const BalanceLineChart(
          semanticLabel: 'x',
          lines: [
            ChartLine(values: [3], color: Colors.blue),
          ],
        ),
      ),
    );
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots, hasLength(2));
  });

  testWidgets('donut shows its centre text and survives all-zero data', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ShareDonut(
          semanticLabel: 'Owed',
          centre: '£0',
          caption: 'total owed',
          slices: [(value: 0, color: Colors.red)],
        ),
      ),
    );
    expect(find.text('£0'), findsOneWidget);
    expect(find.bySemanticsLabel('Owed'), findsOneWidget);
  });

  testWidgets('stacked chart hides a debt by flattening its band', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        StackedBalanceChart(
          semanticLabel: 'Stack',
          stacks: const [
            [2, 5],
            [1, 3],
            [0, 0],
          ],
          colors: const [Colors.red, Colors.blue],
          names: const ['A', 'B'],
          hidden: const {0},
          tooltip: (m, balances, total) => 'Month $m',
        ),
      ),
    );
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    // Drawn tallest first: B's band tops out at B alone once A is hidden.
    expect(chart.data.lineBarsData.first.spots.first.y, 3);
    expect(find.bySemanticsLabel('Stack'), findsOneWidget);
  });

  testWidgets('segment bar and comparison bars render', (tester) async {
    await tester.pumpWidget(
      host(
        const Column(
          children: [
            SegmentBar(
              semanticLabel: 'Split',
              segments: [
                Segment(3, Colors.grey),
                Segment(1, Colors.black, hazard: true),
              ],
            ),
            ComparisonBars(
              semanticLabel: 'Compare',
              bars: [
                ComparisonBar(label: 'Now', value: 2, trailing: 'Nov 28'),
                ComparisonBar(
                  label: 'More',
                  value: 1,
                  trailing: 'Jun 28',
                  highlight: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('Split'), findsOneWidget);
    expect(find.bySemanticsLabel('Compare'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('a card heading keeps its note at the far edge', (tester) async {
    await tester.pumpWidget(
      host(
        const OutlinedCard(
          title: 'Pay this month',
          trailing: '£1,000.00',
          child: SizedBox(height: 10),
        ),
      ),
    );
    final card = tester.getRect(find.byType(OutlinedCard));
    final note = tester.getRect(find.text('£1,000.00'));
    expect(card.right - note.right, lessThan(20)); // 14px padding + border
  });
}
