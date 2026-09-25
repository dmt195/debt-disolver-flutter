import 'package:debt_destroyer/app/theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Lines are told apart by style as well as colour (spec §5.1).
enum LineStyle { solid, dashed, dotted }

class ChartLine {
  const ChartLine({
    required this.values,
    required this.color,
    this.style = LineStyle.solid,
    this.width = 2.5,
    this.label,
  });

  /// One value per month, from month 0.
  final List<double> values;
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
    super.key,
  });

  final List<ChartLine> lines;
  final String semanticLabel;
  final double height;
  final bool compact;
  final String? startLabel;
  final String? endLabel;

  static List<FlSpot> _spots(List<double> values) => [
    for (final (i, y) in values.indexed) FlSpot(i.toDouble(), y),
    if (values.length == 1) FlSpot(1, values.first),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    var maxX = 1;
    var maxY = 0.0;
    for (final l in lines) {
      if (l.values.length - 1 > maxX) maxX = l.values.length - 1;
      for (final v in l.values) {
        if (v > maxY) maxY = v;
      }
    }
    final chart = LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX.toDouble(),
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
        lineBarsData: [
          for (final l in lines)
            LineChartBarData(
              spots: _spots(l.values),
              color: l.color,
              barWidth: l.width,
              isCurved: true,
              curveSmoothness: 0.2,
              preventCurveOverShooting: true,
              dotData: const FlDotData(show: false),
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
