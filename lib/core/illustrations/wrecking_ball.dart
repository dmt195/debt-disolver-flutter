import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:debt_destroyer/core/illustrations/illustration.dart';
import 'package:debt_destroyer/core/illustrations/kit.dart';
import 'package:debt_destroyer/core/illustrations/scenes.dart';
import 'package:flutter/widgets.dart';

/// A debt cleared (spec §4.10): the ball swings in from the left over the
/// first half of [progress], bricks scatter over 0.4–0.9 and settle on the
/// ground. Drawn for a hi-vis page.
class WreckingBallScene extends StatelessWidget {
  const WreckingBallScene({required this.progress, super.key});

  final double progress;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 190),
    child: Center(
      child: Illustration(
        painter: _WreckingBallPainter(progress),
        aspectRatio: _design.width / _design.height,
      ),
    ),
  );
}

/// Every debt cleared: a flag rises on the cleared plot as [progress] runs
/// 0 → 1.
class DebtFreeScene extends StatelessWidget {
  const DebtFreeScene({required this.progress, super.key});

  final double progress;

  @override
  Widget build(BuildContext context) => ClearedPlot(
    raise: Curves.easeOutBack.transform(progress.clamp(0, 1)).clamp(0, 1.05),
    maxHeight: 190,
    flag: kWhite,
  );
}

const _design = Size(200, 120);
const _ground = 112.0;
const _anchor = Offset(40, 0);
const _chain = 74.0;
const _radius = 14.0;
const _brick = Size(22, 11);

/// Where each hit brick starts (row, col in a 3 × 5 wall) and where it
/// lands: its centre beside the wall, and how far it turns.
const _scatter = [
  (4, 0, Offset(170, 106), 0.0),
  (3, 0, Offset(188, 106), 0.0),
  (4, 1, Offset(179, 95), 0.2),
  (2, 0, Offset(162, 97), -0.9),
  (3, 1, Offset(191, 90), 1.3),
];

Rect _wallBrick(int row, int col) => Rect.fromLTWH(
  82 + col * (_brick.width + 2) + (row.isOdd ? 6 : 0),
  _ground - (row + 1) * (_brick.height + 2),
  _brick.width,
  _brick.height,
);

double _phase(double t, double from, double to) =>
    ((t - from) / (to - from)).clamp(0.0, 1.0);

class _WreckingBallPainter extends CustomPainter {
  const _WreckingBallPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (designScale(size, _design) == 0) return;
    fitDesign(canvas, size, _design);
    final t = progress.clamp(0.0, 1.0);
    drawGround(canvas, _design.width, _ground);

    // The wall, less the bricks that fly.
    final flying = {for (final (r, c, _, _) in _scatter) (r, c)};
    for (var row = 0; row < 5; row++) {
      for (var col = 0; col < 3; col++) {
        if (!flying.contains((row, col))) {
          drawBrick(canvas, _wallBrick(row, col));
        }
      }
    }

    // Bricks scatter over 0.4–0.9, arcing on to the ground.
    final s = Curves.easeOut.transform(_phase(t, 0.4, 0.9));
    for (final (row, col, to, turn) in _scatter) {
      final from = _wallBrick(row, col).center;
      final lift = 30 * math.sin(math.pi * s);
      drawBrick(
        canvas,
        Rect.fromCenter(
          center: Offset(
            lerpDouble(from.dx, to.dx, s)!,
            lerpDouble(from.dy, to.dy, s)! - lift,
          ),
          width: _brick.width,
          height: _brick.height,
        ),
        fill: kWhite,
        // A full spin on the way, landing at its resting angle.
        turn: (2 * math.pi + turn) * s,
      );
    }

    // The crane arm, then the ball: in from the left over 0–0.5, a small
    // rebound after.
    canvas
      ..drawLine(const Offset(0, 2), const Offset(52, 2), inkStroke(4))
      ..drawCircle(_anchor, 3, fillOf(kInk));
    final swing = t < 0.5
        ? lerpDouble(-1.2, 0.34, Curves.easeIn.transform(_phase(t, 0, 0.5)))!
        : lerpDouble(0.34, 0.12, Curves.easeOut.transform(_phase(t, 0.5, 1)))!;
    final ball =
        _anchor + Offset(math.sin(swing) * _chain, math.cos(swing) * _chain);
    drawBall(canvas, ball, _radius, anchor: _anchor);
  }

  @override
  bool shouldRepaint(_WreckingBallPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
