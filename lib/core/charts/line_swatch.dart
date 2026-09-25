import 'package:debt_destroyer/core/charts/balance_line_chart.dart';
import 'package:flutter/material.dart';

/// A short sample of a chart line, for legends: solid, dashed or dotted.
class LineSwatch extends StatelessWidget {
  const LineSwatch({required this.color, required this.style, super.key});

  final Color color;
  final LineStyle style;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 18,
    child: CustomPaint(
      size: const Size(18, 3),
      painter: _LineSwatchPainter(color, style),
    ),
  );
}

class _LineSwatchPainter extends CustomPainter {
  const _LineSwatchPainter(this.color, this.style);

  final Color color;
  final LineStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5;
    final y = size.height / 2;
    final (dash, gap) = switch (style) {
      LineStyle.solid => (size.width, 0.0),
      LineStyle.dashed => (5.0, 3.0),
      LineStyle.dotted => (2.0, 3.0),
    };
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dash).clamp(0, size.width), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LineSwatchPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.style != style;
}
