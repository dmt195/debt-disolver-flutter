import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:flutter/material.dart';

/// The hi-vis "Cheapest" badge.
class CheapestBadge extends StatelessWidget {
  const CheapestBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: c.hiVis,
        border: Border.all(color: c.onHiVis, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        context.l10n.cheapest,
        style: TextStyle(
          color: c.onHiVis,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
