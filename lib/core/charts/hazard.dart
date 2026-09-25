import 'package:flutter/rendering.dart';

/// "Still to knock down": −45° hi-vis and navy stripes (spec §5.1).
class HazardPainter extends CustomPainter {
  const HazardPainter({this.stripe = 7});

  final double stripe;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..clipRect(Offset.zero & size)
      ..drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFC400));
    final navy = Paint()..color = const Color(0xFF14213D);
    for (var x = -size.height; x < size.width + size.height; x += stripe * 2) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + stripe, size.height)
        ..lineTo(x + stripe + size.height, 0)
        ..lineTo(x + size.height, 0)
        ..close();
      canvas.drawPath(path, navy);
    }
  }

  @override
  bool shouldRepaint(HazardPainter oldDelegate) => oldDelegate.stripe != stripe;
}
