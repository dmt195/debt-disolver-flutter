import 'package:debt_destroyer/app/theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Lines are told apart by style as well as colour (spec §5.1).
enum LineStyle { solid, dashed, dotted }

class ChartLine {
  const ChartLine({
    required this.color,
    this.values = const [],
    this.points,
    this.squares = false,
    this.style = LineStyle.solid,
    this.width = 2.5,
    this.label,
  });

  /// One value per month, from month 0.
  final List<double> values;

  /// (x, y) points instead of [values], for data that isn't monthly (such
  /// as check-ins).
  final List<(double, double)>? points;

  /// Marks each point with a small square (check-ins, spec §4.2).
  final bool squares;
  final Color color;
  final LineStyle style;
  final double width;
  final String? label;
}

/// Balances over time as lines: the race to zero, Home's projection, and
/// sparklines ([compact]: no axes, grid or labels).
class BalanceLineChart extends StatelessWidget {
  const BalanceLineChart({
    required this.lines,
    required this.semanticLabel,
    this.height = 150,
    this.compact = false,
    this.startLabel,
    this.endLabel,
    this.todayX,
    this.markers = const [],
    super.key,
  });

  final List<ChartLine> lines;

  /// Where to draw the "today" line, if anywhere.
  final double? todayX;

  /// Short ticks on the time axis: restarts and plan switches.
  final List<({double x, String label})> markers;
  final String semanticLabel;
  final double height;
  final bool compact;
  final String? startLabel;
  final String? endLabel;

  static List<FlSpot> _spots(ChartLine line) {
    if (line.points case final points?) {
      return [for (final (x, y) in points) FlSpot(x, y)];
    }
    final values = line.values;
    return [
      for (final (i, y) in values.indexed) FlSpot(i.toDouble(), y),
      if (values.length == 1) FlSpot(1, values.first),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    var maxX = 1.0;
    var maxY = 0.0;
    for (final l in lines) {
      for (final spot in _spots(l)) {
        if (spot.x > maxX) maxX = spot.x;
        if (spot.y > maxY) maxY = spot.y;
      }
    }
    final chart = LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: maxY <= 0 ? 1 : maxY * 1.05,
        lineTouchData: const LineTouchData(enabled: false),
        borderData: FlBorderData(
          show: !compact,
          border: Border(bottom: BorderSide(color: c.ink, width: 1.5)),
        ),
        gridData: FlGridData(
          show: !compact,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: c.track, strokeWidth: 1),
        ),
        titlesData: const FlTitlesData(show: false),
        extraLinesData: ExtraLinesData(
          verticalLines: [
            for (final m in markers)
              VerticalLine(
                x: m.x,
                color: c.ink2,
                dashArray: const [3, 3],
              ),
            if (todayX case final today?)
              VerticalLine(x: today, color: c.today, strokeWidth: 1.5),
          ],
        ),
        // Painted last-first, so the first line sits on top.
        lineBarsData: [
          for (final l in lines.reversed)
            LineChartBarData(
              spots: _spots(l),
              color: l.color,
              barWidth: l.width,
              // Monthly steps: straight segments, never smoothed.
              dotData: FlDotData(
                show: l.squares,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotSquarePainter(
                      size: 8,
                      color: l.color,
                      strokeWidth: 2,
                      strokeColor: c.surface,
                    ),
              ),
              dashArray: switch (l.style) {
                LineStyle.solid => null,
                LineStyle.dashed => const [7, 4],
                LineStyle.dotted => const [2, 4],
              },
            ),
        ],
      ),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 400),
    );
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: height, child: chart),
          if (!compact && (startLabel != null || endLabel != null))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Text(
                    startLabel ?? '',
                    style: TextStyle(fontSize: 11, color: c.ink2),
                  ),
                  const Spacer(),
                  Text(
                    endLabel ?? '',
                    style: TextStyle(fontSize: 11, color: c.ink2),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
