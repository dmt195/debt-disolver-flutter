import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Direction A's fixed inks (spec §5.2): navy outlines, hi-vis as the only
/// highlight, flat fills. Illustrations use these in light and dark alike.
const kInk = Color(0xFF14213D);
const kHiVis = Color(0xFFFFC400);
const kBrickFill = Color(0xFFE3E6EB);
const kWhite = Color(0xFFFFFFFF);

/// The navy outline, 2 design px.
Paint inkStroke([double width = 2]) => Paint()
  ..color = kInk
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round;

Paint fillOf(Color color) => Paint()..color = color;

/// How much a [design] box is scaled to fit inside [size], keeping its shape.
double designScale(Size size, Size design) {
  if (size.isEmpty || design.isEmpty) return 0;
  return math.min(size.width / design.width, size.height / design.height);
}

/// Scales and centres the canvas so a painter can draw in [design]
/// coordinates whatever size it is given.
void fitDesign(Canvas canvas, Size size, Size design) {
  final scale = designScale(size, design);
  canvas
    ..translate(
      (size.width - design.width * scale) / 2,
      (size.height - design.height * scale) / 2,
    )
    ..scale(scale);
}

/// One brick: a rounded, outlined block, turned [turn] radians about its
/// centre.
void drawBrick(
  Canvas canvas,
  Rect rect, {
  Color fill = kBrickFill,
  double turn = 0,
}) {
  final shape = RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: Offset.zero,
      width: rect.width,
      height: rect.height,
    ),
    const Radius.circular(2),
  );
  canvas
    ..save()
    ..translate(rect.center.dx, rect.center.dy)
    ..rotate(turn)
    ..drawRRect(shape, fillOf(fill))
    ..drawRRect(shape, inkStroke())
    ..restore();
}

/// The ground line across [width] at [y].
void drawGround(Canvas canvas, double width, double y) =>
    canvas.drawLine(Offset(0, y), Offset(width, y), inkStroke(3));

/// A wrecking ball of [radius] at [centre], hanging by a chain from
/// [anchor] when given.
void drawBall(Canvas canvas, Offset centre, double radius, {Offset? anchor}) {
  if (anchor != null) canvas.drawLine(anchor, centre, inkStroke(2.5));
  canvas
    ..drawCircle(centre, radius, fillOf(kInk))
    // A highlight so the ball reads as round on navy grounds too.
    ..drawCircle(
      centre.translate(-radius * 0.35, -radius * 0.35),
      radius * 0.18,
      fillOf(kWhite.withValues(alpha: 0.5)),
    );
}

/// A flag pole [height] tall standing at [base], its flag ([fill], hi-vis
/// by default) [raise]d (0–1) of the way up.
void drawFlag(
  Canvas canvas,
  Offset base,
  double height, {
  double raise = 1,
  Color fill = kHiVis,
}) {
  final top = base.translate(0, -height);
  canvas.drawLine(base, top, inkStroke(3));
  final flagHeight = height * 0.28;
  final y = base.dy - flagHeight - (height - flagHeight) * raise.clamp(0, 1);
  final flag = Path()
    ..moveTo(base.dx, y)
    ..lineTo(base.dx + height * 0.42, y + flagHeight / 2)
    ..lineTo(base.dx, y + flagHeight)
    ..close();
  canvas
    ..drawPath(flag, fillOf(fill))
    ..drawPath(flag, inkStroke());
}
