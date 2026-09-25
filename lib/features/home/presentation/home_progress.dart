import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/charts/balance_line_chart.dart';
import 'package:debt_destroyer/core/charts/line_swatch.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/core/widgets/outlined_card.dart';
import 'package:debt_destroyer/features/progress/domain/progress.dart';
import 'package:debt_destroyer/features/progress/domain/progress_math.dart';
import 'package:debt_destroyer/features/progress/presentation/progress_providers.dart';
import 'package:debt_destroyer/features/progress/presentation/restart_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// The share paid off, as a ring (spec §4.2).
class ProgressRing extends StatelessWidget {
  const ProgressRing({required this.percent, super.key});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: context.l10n.homePercentPaid(percent),
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 84,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.square(
              dimension: 76,
              child: CircularProgressIndicator(
                value: percent / 100,
                strokeWidth: 10,
                color: c.onHiVis,
                backgroundColor: c.onHiVis.withValues(alpha: 0.2),
              ),
            ),
            Text('$percent%', style: displayStyle(18, color: c.onHiVis)),
          ],
        ),
      ),
    );
  }
}

/// "2 months ahead", "£110 ahead", "On track", "£80 behind"…
String standingText(
  AppLocalizations l10n,
  AheadBehind standing,
  String locale,
) => switch (standing) {
  NoProgressYet() => l10n.homeCheckInToTrack,
  OnTrack() => l10n.homeOnTrack,
  AheadMonths(:final months) => l10n.homeAheadMonths(months),
  AheadMoney(:final amount) => l10n.homeAheadMoney(formatMoney(amount, locale)),
  Behind(:final amount) => l10n.homeBehind(formatMoney(amount, locale)),
};

/// The chip for [standing]: navy, white text.
class StandingChip extends StatelessWidget {
  const StandingChip({required this.standing, super.key});

  final AheadBehind standing;

  @override
  Widget build(BuildContext context) => Consumer(
    builder: (context, ref, _) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF14213D),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        standingText(context.l10n, standing, ref.watch(formatLocaleProvider)),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// Why a restart happened, for the chart's legend.
String restartLabel(
  AppLocalizations l10n,
  ({double x, StartReason reason, StrategyId strategy, String? debtName})
  marker,
) => switch (marker.reason) {
  StartReason.planSwitched => l10n.restartSwitched(
    strategyName(l10n, marker.strategy),
  ),
  StartReason.debtAdded => l10n.restartAdded(marker.debtName ?? ''),
  StartReason.debtDeleted => l10n.restartDeleted(marker.debtName ?? ''),
  StartReason.restarted || StartReason.initial => l10n.restartRestarted,
};

/// Plan against actual (spec §6.7): check-ins, the plan from the latest
/// starting point and, after a restart, the original plan.
class ProgressChartCard extends ConsumerWidget {
  const ProgressChartCard({
    required this.chart,
    required this.debtFree,
    this.trailing,
    this.onTap,
    super.key,
  });

  final ProgressChart chart;
  final DateTime debtFree;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final locale = ref.watch(formatLocaleProvider);
    final history = ref.watch(progressHistoryProvider).value;
    final first = history?.firstStart?.at ?? DateTime.now();
    final lines = [
      ChartLine(
        points: chart.actual,
        color: c.series.first,
        squares: true,
        width: 3,
        label: l10n.homeProgressActual,
      ),
      ChartLine(
        points: chart.current,
        color: c.ink,
        style: LineStyle.dashed,
        width: 2,
        label: l10n.homeProgressPlan,
      ),
      if (chart.original case final original?)
        ChartLine(
          points: original,
          color: c.faint,
          style: LineStyle.dotted,
          width: 2,
          label: l10n.homeProgressOriginal,
        ),
    ];
    var maxX = 0.0;
    for (final l in lines) {
      for (final (x, _) in l.points!) {
        if (x > maxX) maxX = x;
      }
    }
    String month(double x) =>
        DateFormat.yMMM(locale)
            .format(DateTime(first.year, first.month + x.ceil()));
    final owed = chart.actual.isEmpty ? 0.0 : chart.actual.last.$2;
    final card = OutlinedCard(
      title: l10n.homeProgressTitle,
      trailing: trailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BalanceLineChart(
            lines: lines,
            todayX: chart.today,
            markers: [
              for (final m in chart.markers)
                (x: m.x, label: restartLabel(l10n, m)),
            ],
            semanticLabel: l10n.homeProgressLabel(
              NumberFormat.decimalPattern(locale).format(owed.round()),
              DateFormat.yMMMM(locale).format(debtFree),
            ),
            startLabel: month(0),
            endLabel: month(maxX),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final line in lines)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LineSwatch(color: line.color, style: line.style),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        line.label ?? '',
                        style: TextStyle(fontSize: 11.5, color: c.ink2),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          for (final m in chart.markers)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${month(m.x)}: ${restartLabel(l10n, m)}',
                style: TextStyle(fontSize: 11.5, color: c.ink2),
              ),
            ),
        ],
      ),
    );
    return onTap == null
        ? card
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: card,
          );
  }
}

/// When you last checked in, with the way to do it again or restart.
class CheckInCard extends ConsumerWidget {
  const CheckInCard({required this.lastCheckIn, super.key});

  final CheckIn? lastCheckIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final locale = ref.watch(formatLocaleProvider);
    final last = lastCheckIn;
    return OutlinedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            last == null || last.isStart
                ? l10n.homeNoCheckInYet
                : l10n.homeLastCheckIn(DateFormat.MMMd(locale).format(last.at)),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: () => context.push(Routes.checkIn),
                child: Text(l10n.homeCheckInNow),
              ),
              TextButton(
                onPressed: () => showRestartSheet(context),
                style: TextButton.styleFrom(foregroundColor: c.ink2),
                child: Text(l10n.homeRestart),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
