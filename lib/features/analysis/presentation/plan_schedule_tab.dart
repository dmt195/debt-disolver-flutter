import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The month-by-month schedule. Rows are built lazily: a plan can run to
/// 1,200 months.
class PlanScheduleTab extends ConsumerWidget {
  const PlanScheduleTab({required this.table, super.key});

  final ScheduleTable table;

  static const double _monthWidth = 64;
  static const double _amountWidth = 132;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(formatLocaleProvider);
    final theme = Theme.of(context);
    final width = _monthWidth + _amountWidth * (table.headers.length - 1) + 16;

    Widget cell(String text, double w, {TextStyle? style, bool end = true}) =>
        SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Text(
              text,
              style: style,
              textAlign: end ? TextAlign.end : TextAlign.start,
            ),
          ),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            Material(
              color: theme.colorScheme.surfaceContainerHigh,
              child: Row(
                children: [
                  for (final (i, h) in table.headers.indexed)
                    cell(
                      h,
                      i == 0 ? _monthWidth : _amountWidth,
                      style: theme.textTheme.labelMedium,
                      end: i != 0,
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: table.rows.length,
                itemBuilder: (context, r) {
                  final row = table.rows[r];
                  return Row(
                    children: [
                      cell('${row.month}', _monthWidth, end: false),
                      for (final amount in row.amounts)
                        cell(formatMoney(amount, locale), _amountWidth),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
