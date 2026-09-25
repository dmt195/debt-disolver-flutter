import 'package:debt_destroyer/core/illustrations/kit.dart';
import 'package:flutter/rendering.dart';

const _design = Size(200, 125);
const _ground = 115.0;

// The welcome art sits on a hi-vis panel, so the brick that matters is
// navy rather than hi-vis.

/// Welcome page 1: a tangle of debts straightens into a path to a flag.
class TangleToPath extends CustomPainter {
  const TangleToPath();

  @override
  void paint(Canvas canvas, Size size) {
    if (designScale(size, _design) == 0) return;
    fitDesign(canvas, size, _design);
    drawGround(canvas, _design.width, _ground);
    final tangle = Path()
      ..moveTo(14, 70)
      ..cubicTo(10, 30, 60, 30, 50, 60)
      ..cubicTo(40, 95, 10, 70, 30, 50)
      ..cubicTo(50, 30, 80, 60, 62, 78)
      ..cubicTo(50, 92, 36, 60, 70, 62)
      ..lineTo(150, 62);
    canvas.drawPath(tangle, inkStroke(3));
    // The straight run ends at a stack of bricks with a flag on top.
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 2; col++) {
        drawBrick(
          canvas,
          Rect.fromLTWH(
            150 + col * 20 + (row.isOdd ? 6 : 0),
            _ground - 13 - row * 13,
            18,
            11,
          ),
          fill: row == 2 && col == 1 ? kInk : kBrickFill,
        );
      }
    }
    drawFlag(canvas, const Offset(172, _ground - 39), 44);
  }

  @override
  bool shouldRepaint(TangleToPath oldDelegate) => false;
}

/// Welcome page 2: stacks of bricks by rate; the ball swings at the tallest.
class HighestRateFirst extends CustomPainter {
  const HighestRateFirst();

  @override
  void paint(Canvas canvas, Size size) {
    if (designScale(size, _design) == 0) return;
    fitDesign(canvas, size, _design);
    drawGround(canvas, _design.width, _ground);
    for (final (x, height, first) in [
      (96.0, 6, true),
      (130.0, 4, false),
      (164.0, 2, false),
    ]) {
      for (var row = 0; row < height; row++) {
        drawBrick(
          canvas,
          Rect.fromLTWH(x, _ground - 13 - row * 13, 26, 11),
          fill: first && row == height - 1 ? kInk : kBrickFill,
        );
      }
    }
    drawBall(canvas, const Offset(58, 42), 16, anchor: const Offset(90, 0));
  }

  @override
  bool shouldRepaint(HighestRateFirst oldDelegate) => false;
}

/// Welcome page 3: a cleared stack's payment rolls on to the next one.
class PaymentsRollOn extends CustomPainter {
  const PaymentsRollOn();

  @override
  void paint(Canvas canvas, Size size) {
    if (designScale(size, _design) == 0) return;
    fitDesign(canvas, size, _design);
    drawGround(canvas, _design.width, _ground);
    // Where the first stack stood.
    final gone = RRect.fromRectAndRadius(
      const Rect.fromLTWH(20, _ground - 13, 30, 11),
      const Radius.circular(2),
    );
    canvas.drawRRect(gone, inkStroke(1.5)..color = kInk.withValues(alpha: 0.4));
    for (final (x, height) in [(86.0, 4), (150.0, 5)]) {
      for (var row = 0; row < height; row++) {
        drawBrick(canvas, Rect.fromLTWH(x, _ground - 13 - row * 13, 30, 11));
      }
    }
    // The payment, a navy brick, arcs on to the next stack.
    final arc = Path()
      ..moveTo(35, _ground - 20)
      ..quadraticBezierTo(62, 20, 96, _ground - 64);
    canvas.drawPath(arc, inkStroke(2.5));
    final head = Path()
      ..moveTo(96, _ground - 64)
      ..lineTo(86, _ground - 68)
      ..moveTo(96, _ground - 64)
      ..lineTo(94, _ground - 75);
    canvas.drawPath(head, inkStroke(2.5));
    drawBrick(
      canvas,
      const Rect.fromLTWH(46, 34, 22, 13),
      fill: kInk,
      turn: 0.5,
    );
  }

  @override
  bool shouldRepaint(PaymentsRollOn oldDelegate) => false;
}

/// Setup: a hard hat beside a small wall, ready to start.
/// It stands on the page's ground, so it draws in the theme's [ink].
class SetupArt extends InkPainter {
  const SetupArt({super.ink});

  static const design = Size(200, 80);

  @override
  void paint(Canvas canvas, Size size) {
    if (designScale(size, design) == 0) return;
    withInk(ink, () => _paint(canvas, size));
  }

  void _paint(Canvas canvas, Size size) {
    fitDesign(canvas, size, design);
    const ground = 72.0;
    drawGround(canvas, design.width, ground);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 4; col++) {
        drawBrick(
          canvas,
          Rect.fromLTWH(
            100 + col * 20 + (row.isOdd ? 8 : 0),
            ground - 13 - row * 13,
            18,
            11,
          ),
        );
      }
    }
    // A hard hat: dome and brim.
    final dome = Path()
      ..moveTo(30, ground - 4)
      ..arcToPoint(
        const Offset(78, ground - 4),
        radius: const Radius.circular(24),
      )
      ..close();
    final brim = RRect.fromRectAndRadius(
      const Rect.fromLTWH(22, ground - 8, 64, 7),
      const Radius.circular(3),
    );
    canvas
      ..drawPath(dome, fillOf(kHiVis))
      ..drawPath(dome, inkStroke())
      ..drawRRect(brim, fillOf(kHiVis))
      ..drawRRect(brim, inkStroke())
      ..drawLine(
        const Offset(54, ground - 28),
        const Offset(54, ground - 8),
        inkStroke(),
      );
  }

  @override
  bool shouldRepaint(SetupArt oldDelegate) => oldDelegate.ink != ink;
}
