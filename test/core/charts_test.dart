import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/charts/balance_line_chart.dart';
import 'package:debt_destroyer/core/charts/comparison_bars.dart';
import 'package:debt_destroyer/core/charts/draw_in.dart';
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

  testWidgets('plots points, squares, a today line and restart ticks', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const BalanceLineChart(
          semanticLabel: 'Progress',
          todayX: 2.5,
          markers: [(x: 2, label: 'Switched to Snowball')],
          lines: [
            ChartLine(
              points: [(0, 1000), (1, 900), (2, 800)],
              color: Colors.blue,
              squares: true,
            ),
            ChartLine(
              points: [(2, 800), (4, 0)],
              color: Colors.black,
              style: LineStyle.dashed,
            ),
          ],
        ),
      ),
    );
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.maxX, 4);
    // The first line is painted last, on top.
    expect(data.lineBarsData.last.spots.map((s) => s.x), [0, 1, 2]);
    expect(data.lineBarsData.last.dotData.show, isTrue);
    expect(data.lineBarsData.first.dotData.show, isFalse);
    expect(
      data.extraLinesData.verticalLines.map((l) => l.x),
      containsAll([2.5, 2.0]),
    );
  });

  group('draw in', () {
    double factor(WidgetTester tester) =>
        (tester
                    .widget<ClipRect>(
                      find.descendant(
                        of: find.byType(DrawIn),
                        matching: find.byType(ClipRect),
                      ),
                    )
                    .clipper!
                as RevealClipper)
            .factor;

    Widget line(List<double> values) => host(
      BalanceLineChart(
        semanticLabel: 'x',
        lines: [ChartLine(values: values, color: Colors.blue)],
      ),
    );

    testWidgets('the line chart draws in left to right, once', (tester) async {
      await tester.pumpWidget(line(const [10, 5, 0]));
      expect(factor(tester), 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(factor(tester), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(factor(tester), 1);
      // New data animates in fl_chart's own way; the reveal stays done.
      await tester.pumpWidget(line(const [12, 6, 1, 0]));
      expect(factor(tester), 1);
    });

    testWidgets('the stacked chart draws in too', (tester) async {
      await tester.pumpWidget(
        host(
          StackedBalanceChart(
            semanticLabel: 'x',
            names: const ['A', 'B'],
            colors: const [Colors.blue, Colors.orange],
            stacks: const [
              [10, 5],
              [6, 3],
              [0, 0],
            ],
            tooltip: (m, balances, total) => '$m',
          ),
        ),
      );
      expect(factor(tester), 0);
      await tester.pumpAndSettle();
      expect(factor(tester), 1);
    });

    testWidgets('with reduced motion, whole at once', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(line(const [10, 5, 0]));
      expect(factor(tester), 1);
    });

    test('the clip grows from the left', () {
      expect(
        const RevealClipper(0.25).getClip(const Size(200, 100)),
        const Rect.fromLTWH(0, 0, 50, 100),
      );
    });
  });
}
