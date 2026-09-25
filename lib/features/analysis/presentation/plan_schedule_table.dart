import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The month-by-month schedule, scrolling sideways when it's wider than the
/// screen, with an arrow at whichever edge has more to see. Shows the first
/// [limit] rows, or all of them when null.
class PlanScheduleTable extends ConsumerStatefulWidget {
  const PlanScheduleTable({required this.table, this.limit, super.key});

  final ScheduleTable table;
  final int? limit;

  @override
  ConsumerState<PlanScheduleTable> createState() => _PlanScheduleTableState();
}

class _PlanScheduleTableState extends ConsumerState<PlanScheduleTable> {
  static const double _monthWidth = 64;
  static const double _amountWidth = 132;

  final _scroll = ScrollController();
  var _moreLeft = false;
  var _moreRight = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Shows the cues that fit where the table is scrolled to.
  bool _update(ScrollMetrics m) {
    final left = m.extentBefore > 1;
    final right = m.extentAfter > 1;
    if (left != _moreLeft || right != _moreRight) {
      // Metrics arrive during layout; change the cues after it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _moreLeft = left;
            _moreRight = right;
          });
        }
      });
    }
    return false;
  }

  void _page(int direction) {
    final p = _scroll.position;
    final target = (p.pixels + direction * p.viewportDimension * 0.8).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final limit = widget.limit;
    final locale = ref.watch(formatLocaleProvider);
    final c = context.colors;
    final rows = limit == null ? table.rows : table.rows.take(limit);

    Widget cell(String text, double w, {TextStyle? style, bool end = true}) =>
        SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Text(
              text,
              style: style,
              textAlign: end ? TextAlign.end : TextAlign.start,
            ),
          ),
        );

    final l10n = context.l10n;
    final scroller = NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _update(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _update(n.metrics),
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (final (i, h) in table.headers.indexed)
                    cell(
                      h,
                      i == 0 ? _monthWidth : _amountWidth,
                      style: TextStyle(fontSize: 12, color: c.ink2),
                      end: i != 0,
                    ),
                ],
              ),
              for (final row in rows)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.track)),
                  ),
                  child: Row(
                    children: [
                      cell('${row.month}', _monthWidth, end: false),
                      for (final amount in row.amounts)
                        cell(
                          formatMoney(amount, locale),
                          _amountWidth,
                          style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // A fade and an arrow at an edge with more beyond it.
    Widget cue({required bool right}) => Positioned(
      top: 0,
      bottom: 0,
      left: right ? null : 0,
      right: right ? 0 : null,
      child: Container(
        width: 44,
        alignment: right ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: right ? Alignment.centerLeft : Alignment.centerRight,
            end: right ? Alignment.centerRight : Alignment.centerLeft,
            colors: [c.surface.withValues(alpha: 0), c.surface],
          ),
        ),
        child: IconButton.filled(
          tooltip: right ? l10n.scheduleScrollRight : l10n.scheduleScrollLeft,
          onPressed: () => _page(right ? 1 : -1),
          style: IconButton.styleFrom(
            backgroundColor: c.ink,
            foregroundColor: c.surface,
            minimumSize: const Size(32, 32),
            fixedSize: const Size(32, 32),
            padding: EdgeInsets.zero,
          ),
          icon: Icon(
            right ? Icons.chevron_right : Icons.chevron_left,
            size: 20,
          ),
        ),
      ),
    );

    return Stack(
      children: [
        scroller,
        if (_moreLeft) cue(right: false),
        if (_moreRight) cue(right: true),
      ],
    );
  }
}
