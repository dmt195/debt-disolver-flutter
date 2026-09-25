import 'package:debt_destroyer/app/theme.dart';
import 'package:flutter/material.dart';

/// The one hi-vis hero block on a screen: yellow, navy outline, navy text.
class HiVisBlock extends StatelessWidget {
  const HiVisBlock({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.hiVis,
        border: Border.all(color: c.onHiVis, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: padding,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: c.onHiVis),
          child: IconTheme.merge(
            data: IconThemeData(color: c.onHiVis),
            child: child,
          ),
        ),
      ),
    );
  }
}
