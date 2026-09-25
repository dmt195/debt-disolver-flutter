import 'package:debt_destroyer/app/theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Each part's share of a whole, with the total in the middle.
class ShareDonut extends StatelessWidget {
  const ShareDonut({
    required this.slices,
    required this.centre,
    required this.caption,
    required this.semanticLabel,
    this.size = 128,
    super.key,
  });

  final List<({double value, Color color})> slices;
  final String centre;
  final String caption;
  final String semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = slices.fold<double>(0, (s, x) => s + x.value);
    PieChartSectionData section(double value, Color color) =>
        PieChartSectionData(
          value: value,
          color: color,
          radius: size * 0.14,
          showTitle: false,
        );
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                startDegreeOffset: -90,
                sectionsSpace: total > 0 ? 2 : 0,
                centerSpaceRadius: size * 0.32,
                sections: total > 0
                    ? [
                        for (final s in slices)
                          if (s.value > 0) section(s.value, s.color),
                      ]
                    : [section(1, c.track)],
              ),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
            ),
            SizedBox(
              width: size * 0.6,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    child: Text(
                      centre,
                      style: displayStyle(size * 0.15, color: c.ink),
                    ),
                  ),
                  FittedBox(
                    child: Text(
                      caption,
                      style: TextStyle(fontSize: 11, color: c.ink2),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
