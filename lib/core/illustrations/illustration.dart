import 'package:flutter/widgets.dart';

/// A drawn illustration at a fixed shape. Decorative unless given a
/// [semanticLabel].
class Illustration extends StatelessWidget {
  const Illustration({
    required this.painter,
    this.aspectRatio = 1.6,
    this.semanticLabel,
    super.key,
  });

  final CustomPainter painter;
  final double aspectRatio;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final art = AspectRatio(
      aspectRatio: aspectRatio,
      child: CustomPaint(painter: painter, size: Size.infinite),
    );
    return switch (semanticLabel) {
      final label? => Semantics(label: label, image: true, child: art),
      null => ExcludeSemantics(child: art),
    };
  }
}
