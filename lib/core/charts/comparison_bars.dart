import 'package:debt_destroyer/app/theme.dart';
import 'package:flutter/material.dart';

class ComparisonBar {
  const ComparisonBar({
    required this.label,
    required this.value,
    required this.trailing,
    this.highlight = false,
  });

  final String label;
  final double value;
  final String trailing;
  final bool highlight;
}

/// Labelled horizontal bars scaled to the largest value.
class ComparisonBars extends StatelessWidget {
  const ComparisonBars({
    required this.bars,
    required this.semanticLabel,
    super.key,
  });

  final List<ComparisonBar> bars;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final max = bars.fold<double>(0, (m, b) => b.value > m ? b.value : m);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in bars)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          b.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(b.trailing),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LayoutBuilder(
                    builder: (context, box) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 16,
                        width: max <= 0 ? 0 : box.maxWidth * b.value / max,
                        decoration: BoxDecoration(
                          color: b.highlight ? c.hiVis : c.ink2,
                          border: b.highlight
                              ? Border.all(color: c.onHiVis, width: 2)
                              : null,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
