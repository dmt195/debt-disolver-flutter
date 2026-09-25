import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The month-by-month schedule, scrolling sideways when it's wider than the
/// screen. Shows the first [limit] rows, or all of them when null.
class PlanScheduleTable extends ConsumerWidget {
  const PlanScheduleTable({required this.table, this.limit, super.key});

  final ScheduleTable table;
  final int? limit;

  static const double _monthWidth = 64;
  static const double _amountWidth = 132;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(formatLocaleProvider);
    final c = context.colors;
    final rows = limit == null ? table.rows : table.rows.take(limit!);

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

    return SingleChildScrollView(
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
    );
  }
}
