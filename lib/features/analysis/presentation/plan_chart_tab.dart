import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Balances over time, stacked by debt: the top line is the total owed.
class PlanChartTab extends ConsumerWidget {
  const PlanChartTab({required this.plan, super.key});

  final PayoffPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final scheme = Theme.of(context).colorScheme;
    final colors = chartColors(scheme);
    final stacks = stackedBalances(plan);
    final currency = plan.totalPaid.currency;
    final compact = NumberFormat.compactSimpleCurrency(
      locale: locale,
      name: currency,
    );

    // Draw the tallest stack first so each lower band paints over it.
    final bars = [
      for (var i = plan.debts.length - 1; i >= 0; i--)
        LineChartBarData(
          spots: [
            for (final (month, totals) in stacks.indexed)
              FlSpot(month.toDouble(), totals[i]),
          ],
          color: colors[i % colors.length],
          barWidth: 1.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: colors[i % colors.length].withValues(alpha: 0.35),
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              l10n.chartTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                lineBarsData: bars,
                lineTouchData: const LineTouchData(enabled: false),
                gridData: const FlGridData(drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 56,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          compact.format(value),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: Text(l10n.scheduleMonth),
                    sideTitles: const SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final (i, debt) in plan.debts.indexed)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      color: colors[i % colors.length],
                    ),
                    const SizedBox(width: 4),
                    Text(planDebtName(l10n, debt)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A distinguishable colour per debt, taken from the theme.
List<Color> chartColors(ColorScheme scheme) => [
  scheme.primary,
  scheme.tertiary,
  scheme.secondary,
  scheme.error,
  scheme.primaryFixedDim,
  scheme.tertiaryFixedDim,
  scheme.secondaryFixedDim,
];

/// For month 0 (starting balances) through the last month, the cumulative
/// balance in major units: element `i` is the sum of debts `0..i`.
List<List<double>> stackedBalances(PayoffPlan plan) {
  final digits = currencyDecimalDigits(plan.totalPaid.currency);
  var scale = 1;
  for (var i = 0; i < digits; i++) {
    scale *= 10;
  }
  List<double> cumulative(List<Money> balances) {
    var running = 0;
    return [for (final b in balances) (running += b.minor) / scale];
  }

  return [
    cumulative([for (final d in plan.debts) d.startingBalance]),
    for (final row in plan.months) cumulative(row.closingBalances),
  ];
}
