import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/illustrations/brick_wall.dart';
import 'package:debt_destroyer/core/illustrations/illustration.dart';
import 'package:debt_destroyer/core/illustrations/kit.dart';
import 'package:flutter/widgets.dart';

const _design = Size(200, 100);
const _ground = 92.0;

/// A scene no taller than [maxHeight], centred in the width it's given.
Widget _scene(CustomPainter painter, {double maxHeight = 140}) =>
    ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Center(
        child: Illustration(
          painter: painter,
          aspectRatio: _design.width / _design.height,
        ),
      ),
    );

/// Nothing built yet: an empty lot with a cone and a few loose bricks.
class EmptyLot extends StatelessWidget {
  const EmptyLot({super.key});

  @override
  Widget build(BuildContext context) =>
      _scene(_EmptyLotPainter(ink: context.colors.ink));
}

class _EmptyLotPainter extends InkPainter {
  const _EmptyLotPainter({super.ink});

  @override
  void paint(Canvas canvas, Size size) {
    if (designScale(size, _design) == 0) return;
    withInk(ink, () => _paint(canvas, size));
  }

  void _paint(Canvas canvas, Size size) {
    fitDesign(canvas, size, _design);
    drawGround(canvas, _design.width, _ground);
    drawBrick(canvas, const Rect.fromLTWH(40, _ground - 12, 22, 11));
    drawBrick(canvas, const Rect.fromLTWH(64, _ground - 12, 22, 11));
    drawBrick(canvas, const Rect.fromLTWH(52, _ground - 24, 22, 11), turn: 0.2);
    _cone(canvas, const Offset(140, _ground), 44);
  }

  @override
  bool shouldRepaint(_EmptyLotPainter oldDelegate) => oldDelegate.ink != ink;
}

/// A traffic cone [height] tall standing at [base].
void _cone(Canvas canvas, Offset base, double height) {
  final half = height * 0.32;
  final cone = Path()
    ..moveTo(base.dx - half, base.dy - 4)
    ..lineTo(base.dx - 5, base.dy - height)
    ..lineTo(base.dx + 5, base.dy - height)
    ..lineTo(base.dx + half, base.dy - 4)
    ..close();
  canvas
    ..drawPath(cone, fillOf(kHiVis))
    ..drawPath(cone, inkStroke());
  // A white band.
  final y = base.dy - height * 0.55;
  final band = Rect.fromLTRB(
    base.dx - half * 0.6,
    y - 4,
    base.dx + half * 0.6,
    y + 4,
  );
  canvas
    ..drawRect(band, fillOf(kWhite))
    ..drawRect(band, inkStroke(1.5))
    ..drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          base.dx - half - 6,
          base.dy - 5,
          base.dx + half + 6,
          base.dy,
        ),
        const Radius.circular(2),
      ),
      inkStroke(),
    );
}

/// No saved scenarios: a signpost with two ways to go.
class Signpost extends StatelessWidget {
  const Signpost({super.key});

  @override
  Widget build(BuildContext context) =>
      _scene(_SignpostPainter(ink: context.colors.ink));
}

class _SignpostPainter extends InkPainter {
  const _SignpostPainter({super.ink});

  @override
  void paint(Canvas canvas, Size size) {
    if (designScale(size, _design) == 0) return;
    withInk(ink, () => _paint(canvas, size));
  }

  void _paint(Canvas canvas, Size size) {
    fitDesign(canvas, size, _design);
    drawGround(canvas, _design.width, _ground);
    canvas.drawLine(
      const Offset(100, _ground),
      const Offset(100, 14),
      inkStroke(4),
    );
    for (final (y, right, fill) in [
      (18.0, true, kHiVis),
      (44.0, false, kWhite),
    ]) {
      final dir = right ? 1.0 : -1.0;
      final board = Path()
        ..moveTo(100, y)
        ..lineTo(100 + dir * 48, y)
        ..lineTo(100 + dir * 60, y + 9)
        ..lineTo(100 + dir * 48, y + 18)
        ..lineTo(100, y + 18)
        ..close();
      canvas
        ..drawPath(board, fillOf(fill))
        ..drawPath(board, inkStroke());
    }
  }

  @override
  bool shouldRepaint(_SignpostPainter oldDelegate) => oldDelegate.ink != ink;
}

/// The check-in result: the wall losing its paid-off bricks as [progress]
/// runs 0 → 1, a flag going up on top.
class ClimbWall extends StatelessWidget {
  const ClimbWall({required this.percent, this.progress = 1, super.key});

  final int percent;
  final double progress;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 120),
    child: Center(
      child: Illustration(
        painter: _ClimbWallPainter(percent, progress, ink: context.colors.ink),
        aspectRatio: 1.7,
      ),
    ),
  );
}

class _ClimbWallPainter extends InkPainter {
  const _ClimbWallPainter(this.percent, this.progress, {super.ink});

  final int percent;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const design = Size(170, 100);
    if (designScale(size, design) == 0) return;
    final t = progress.clamp(0.0, 1.0);
    final now = (percent.clamp(0, 100) * t).round();
    canvas.save();
    BrickWallPainter(percent: now, progress: t, ink: ink).paint(canvas, size);
    canvas.restore();
    fitDesign(canvas, size, design);
    withInk(ink, () => drawFlag(canvas, climbFlagBase(now), 28, raise: t));
  }

  @override
  bool shouldRepaint(_ClimbWallPainter oldDelegate) =>
      oldDelegate.percent != percent ||
      oldDelegate.progress != progress ||
      oldDelegate.ink != ink;
}

/// Where the check-in flag stands with [percent] paid: on the highest brick
/// left at the wall's left end, or on the ground once that column is gone.
Offset climbFlagBase(int percent) {
  final gone = knockedOut(percent).toSet();
  for (var row = 0; row < 5; row++) {
    if (!gone.contains((row, 0))) {
      final brick = wallBrickRect(row, 0);
      return Offset(brick.center.dx, brick.top);
    }
  }
  return Offset(wallBrickRect(0, 0).center.dx, wallGround);
}

/// Debt-free: a cleared plot, the bricks stacked neatly, a flag [raise]d
/// (0–1) in the middle.
class ClearedPlot extends StatelessWidget {
  const ClearedPlot({
    this.raise = 1,
    this.maxHeight = 140,
    this.flag = kHiVis,
    this.ink,
    super.key,
  });

  final double raise;
  final double maxHeight;

  /// The flag's colour: white where the ground is hi-vis.
  final Color flag;

  /// The outlines: the theme's ink unless given (navy on hi-vis).
  final Color? ink;

  @override
  Widget build(BuildContext context) => _scene(
    _ClearedPlotPainter(raise, flag, ink: ink ?? context.colors.ink),
    maxHeight: maxHeight,
  );
}

class _ClearedPlotPainter extends InkPainter {
  const _ClearedPlotPainter(this.raise, this.flag, {super.ink});

  final double raise;
  final Color flag;

  @override
  void paint(Canvas canvas, Size size) {
    if (designScale(size, _design) == 0) return;
    withInk(ink, () => _paint(canvas, size));
  }

  void _paint(Canvas canvas, Size size) {
    fitDesign(canvas, size, _design);
    drawGround(canvas, _design.width, _ground);
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3 - row; col++) {
        drawBrick(
          canvas,
          Rect.fromLTWH(
            20 + col * 22 + row * 11,
            _ground - 12 - row * 12,
            20,
            11,
          ),
        );
      }
    }
    drawFlag(canvas, const Offset(130, _ground), 70, raise: raise, fill: flag);
  }

  @override
  bool shouldRepaint(_ClearedPlotPainter oldDelegate) =>
      oldDelegate.raise != raise ||
      oldDelegate.flag != flag ||
      oldDelegate.ink != ink;
}
