import 'package:debt_destroyer/app/theme.dart';
import 'package:flutter/material.dart';

/// A 2px-outlined card with an optional heading and trailing note.
class OutlinedCard extends StatelessWidget {
  const OutlinedCard({
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(14),
    super.key,
  });

  final Widget child;
  final String? title;
  final String? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(title!, style: displayStyle(17, color: c.ink)),
                  ),
                  if (trailing != null)
                    Text(
                      trailing!,
                      style: TextStyle(fontSize: 12.5, color: c.ink2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
