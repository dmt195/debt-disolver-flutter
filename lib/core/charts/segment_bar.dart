import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/charts/hazard.dart';
import 'package:flutter/material.dart';

class Segment {
  const Segment(this.value, this.color, {this.hazard = false});

  final double value;
  final Color color;

  /// Drawn in hazard stripes: "still to knock down".
  final bool hazard;
}

/// One bar split into proportional segments.
class SegmentBar extends StatelessWidget {
  const SegmentBar({
    required this.segments,
    required this.semanticLabel,
    this.height = 16,
    super.key,
  });

  final List<Segment> segments;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = segments.fold<double>(0, (s, x) => s + x.value);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.track,
          border: Border.all(color: c.outline, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: total <= 0
            ? null
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final s in segments)
                    if (s.value > 0)
                      Expanded(
                        flex: (s.value / total * 1000).round().clamp(1, 1000),
                        child: s.hazard
                            ? const CustomPaint(painter: HazardPainter())
                            : ColoredBox(color: s.color),
                      ),
                ],
              ),
      ),
    );
  }
}
