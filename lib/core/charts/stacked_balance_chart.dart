import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/charts/draw_in.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Each debt's balance over time, stacked, with a touch scrubber: dragging
/// across shows the month and what is owed on each debt.
class StackedBalanceChart extends StatelessWidget {
  const StackedBalanceChart({
    required this.stacks,
    required this.colors,
    required this.names,
    required this.semanticLabel,
    required this.tooltip,
    this.height = 200,
    this.hidden = const {},
    super.key,
  });

  /// Per month (0 = start): cumulative balances, as `stackedBalances`.
  final List<List<double>> stacks;

  /// Per column of [stacks].
  final List<Color> colors;
  final List<String> names;
  final String semanticLabel;

  /// The tooltip for a month, given each column's own balance (hidden
  /// columns as 0) and the visible total.
  final String Function(int month, List<double> balances, double total) tooltip;
  final double height;

  /// Columns drawn with no height.
  final Set<int> hidden;

  /// [stacks] recomputed without the [hidden] columns.
  List<List<double>> _visible() => [
    for (final row in stacks)
      () {
        var running = 0.0;
        return [
          for (final (i, v) in row.indexed)
            running += hidden.contains(i) ? 0 : v - (i == 0 ? 0 : row[i - 1]),
        ];
      }(),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = _visible();
    final n = names.length;
    double own(List<double> row, int i) => row[i] - (i == 0 ? 0 : row[i - 1]);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: DrawIn(
          child: LineChart(
            LineChartData(
              minY: 0,
              lineBarsData: [
                // Tallest first, so each lower band paints over it.
                for (var i = n - 1; i >= 0; i--)
                  LineChartBarData(
                    spots: [
                      for (final (m, r) in rows.indexed)
                        FlSpot(m.toDouble(), r[i]),
                    ],
                    color: c.surface,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: colors[i]),
                  ),
              ],
              borderData: FlBorderData(
                show: true,
                border: Border(bottom: BorderSide(color: c.ink, width: 1.5)),
              ),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: c.track, strokeWidth: 1),
              ),
              titlesData: const FlTitlesData(show: false),
              lineTouchData: LineTouchData(
                getTouchedSpotIndicator: (bar, indexes) => [
                  for (final _ in indexes)
                    TouchedSpotIndicatorData(
                      FlLine(color: c.ink, strokeWidth: 1.5),
                      const FlDotData(show: false),
                    ),
                ],
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => c.surface,
                  tooltipBorder: BorderSide(color: c.outline, width: 2),
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  maxContentWidth: 180,
                  getTooltipItems: (spots) {
                    if (spots.isEmpty) return const [];
                    final m = spots.first.x.toInt();
                    final row = rows[m];
                    final text = tooltip(m, [
                      for (var i = 0; i < n; i++) own(row, i),
                    ], row.isEmpty ? 0 : row.last);
                    return [
                      LineTooltipItem(
                        text,
                        TextStyle(
                          color: c.ink,
                          fontSize: 12,
                          fontFamily: kBodyFont,
                        ),
                        textAlign: TextAlign.start,
                      ),
                      for (var k = 1; k < spots.length; k++) null,
                    ];
                  },
                ),
              ),
            ),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 400),
          ),
        ),
      ),
    );
  }
}
