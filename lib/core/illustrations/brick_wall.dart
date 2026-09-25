import 'dart:ui' show lerpDouble;

import 'package:debt_destroyer/core/illustrations/illustration.dart';
import 'package:debt_destroyer/core/illustrations/kit.dart';
import 'package:flutter/widgets.dart';

/// The bricks gone from a [rows] × [cols] wall when [percent] is paid off:
/// the top row first, right to left, then the next row down. Each
/// percentage keeps every brick the one before it removed.
List<(int, int)> knockedOut(int percent, {int rows = 5, int cols = 6}) {
  final total = rows * cols;
  final count = (total * percent.clamp(0, 100) / 100).round();
  return [for (var i = 0; i < count; i++) (i ~/ cols, cols - 1 - i % cols)];
}

/// The Home hero's wall: a brick gone for every share paid off (spec §4.2).
/// Two navy bricks (it stands on hi-vis) tumble to the ground as
/// [progress] runs 0 → 1.
class BrickWall extends StatelessWidget {
  const BrickWall({required this.percent, this.progress = 1, super.key});

  final int percent;
  final double progress;

  @override
  Widget build(BuildContext context) => Illustration(
    aspectRatio: _design.width / _design.height,
    painter: BrickWallPainter(percent: percent, progress: progress),
  );
}

const _design = Size(170, 100);
const _rows = 5;
const _cols = 6;
const _brick = Size(18, 11);
const _gap = 2.0;
const _groundY = 96.0;

class BrickWallPainter extends CustomPainter {
  const BrickWallPainter({required this.percent, required this.progress});

  final int percent;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (designScale(size, _design) == 0) return;
    fitDesign(canvas, size, _design);
    final gone = knockedOut(percent).toSet();
    final top = _groundY - _rows * (_brick.height + _gap);
    Rect brickAt(int row, int col) => Rect.fromLTWH(
      4 + col * (_brick.width + _gap) + (row.isOdd ? _brick.width / 2 : 0),
      top + row * (_brick.height + _gap),
      _brick.width,
      _brick.height,
    );
    for (var row = 0; row < _rows; row++) {
      for (var col = 0; col < _cols; col++) {
        if (!gone.contains((row, col))) drawBrick(canvas, brickAt(row, col));
      }
    }
    drawGround(canvas, _design.width, _groundY);
    if (gone.isEmpty) return;
    // Two bricks tumble from the top right onto the ground beside the wall.
    final t = Curves.easeIn.transform(progress.clamp(0, 1));
    for (final (i, landX, spin) in [(0, 146.0, 0.3), (1, 160.0, -0.5)]) {
      final from = brickAt(0, _cols - 1 - i).center;
      final to = Offset(landX, _groundY - _brick.height / 2 - 1);
      final centre = Offset(
        lerpDouble(from.dx, to.dx, t)!,
        lerpDouble(from.dy, to.dy, t)! - 16 * (1 - (2 * t - 1) * (2 * t - 1)),
      );
      drawBrick(
        canvas,
        Rect.fromCenter(
          center: centre,
          width: _brick.width,
          height: _brick.height,
        ),
        fill: kInk,
        turn: spin * t * 3,
      );
    }
  }

  @override
  bool shouldRepaint(BrickWallPainter oldDelegate) =>
      oldDelegate.percent != percent || oldDelegate.progress != progress;
}
