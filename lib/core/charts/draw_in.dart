import 'package:flutter/widgets.dart';

/// Reveals [child] left to right, once, the first time it's shown (spec
/// §5.2). Later changes to the child don't replay it; with reduced motion
/// it shows at once.
class DrawIn extends StatefulWidget {
  const DrawIn({required this.child, super.key});

  final Widget child;

  @override
  State<DrawIn> createState() => _DrawInState();
}

class _DrawInState extends State<DrawIn> with SingleTickerProviderStateMixin {
  late final _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = 1;
    } else if (!_started) {
      _reveal.forward();
    }
    _started = true;
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _reveal,
    builder: (context, child) => ClipRect(
      clipper: RevealClipper(Curves.easeOutCubic.transform(_reveal.value)),
      child: child,
    ),
    child: widget.child,
  );
}

/// Clips to the left [factor] (0–1) of the box; nothing once whole, so
/// tooltips can still spill over the edges.
class RevealClipper extends CustomClipper<Rect> {
  const RevealClipper(this.factor);

  final double factor;

  @override
  Rect getClip(Size size) => factor >= 1
      ? Rect.largest
      : Rect.fromLTWH(0, 0, size.width * factor, size.height);

  @override
  bool shouldReclip(RevealClipper oldClipper) => oldClipper.factor != factor;
}
