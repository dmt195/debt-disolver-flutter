import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/debt_icons.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:flutter/material.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// The kind of debt, picked from a grid of picture tiles (spec §4.4): four
/// across, two when narrow or with large text.
class DebtTypeTiles extends StatelessWidget {
  const DebtTypeTiles({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final DebtType selected;
  final ValueChanged<DebtType> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final columns = MediaQuery.sizeOf(context).width >= 360 && !large ? 4 : 2;
    const types = DebtType.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.fieldType, style: TextStyle(fontSize: 13, color: c.ink2)),
        const SizedBox(height: 6),
        for (var start = 0; start < types.length; start += columns)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = start; i < start + columns; i++) ...[
                    if (i > start) const SizedBox(width: 8),
                    Expanded(
                      child: i < types.length
                          ? _Tile(
                              type: types[i],
                              selected: types[i] == selected,
                              onTap: () => onChanged(types[i]),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final DebtType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = debtTypeLabel(context.l10n, type);
    final background = selected ? c.ink : c.surface;
    final foreground = selected ? c.surface : c.ink;
    final shape = RoundedRectangleBorder(
      side: BorderSide(color: selected ? c.ink : c.outline, width: 2),
      borderRadius: BorderRadius.circular(8),
    );
    return Semantics(
      key: ValueKey('type-${type.name}'),
      button: true,
      selected: selected,
      label: label,
      // The InkWell's own action goes with its excluded semantics, so the
      // tile carries the tap itself.
      onTap: onTap,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Material(
          color: background,
          shape: shape,
          child: InkWell(
            onTap: onTap,
            customBorder: shape,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: selected ? c.hiVis : c.track,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    // Navy on hi-vis; otherwise the ink (light in dark mode).
                    child: Icon(
                      debtTypeIcon(type),
                      size: 20,
                      color: selected ? c.onHiVis : c.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: selected ? FontWeight.w700 : null,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
