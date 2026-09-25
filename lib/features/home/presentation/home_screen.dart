import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/charts/balance_line_chart.dart';
import 'package:debt_destroyer/core/charts/hazard.dart';
import 'package:debt_destroyer/core/debt_colors.dart';
import 'package:debt_destroyer/core/error_view.dart';
import 'package:debt_destroyer/core/illustrations/brick_wall.dart';
import 'package:debt_destroyer/core/illustrations/scenes.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/core/widgets/hi_vis_block.dart';
import 'package:debt_destroyer/core/widgets/outlined_card.dart';
import 'package:debt_destroyer/features/analysis/domain/plan_series.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/home/presentation/home_progress.dart';
import 'package:debt_destroyer/features/progress/presentation/follow_sheet.dart';
import 'package:debt_destroyer/features/progress/presentation/progress_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/presentation/current_plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// The answer first: when you'll be debt-free, how the balance falls, what's
/// next and what to pay this month (spec §4.2).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final body = switch (ref.watch(homePlanProvider)) {
      AsyncData(value: HomeFollowing(:final result, :final baseline))
          when result.plan.monthsToClear > 0 =>
        _Following(result: result, baseline: baseline),
      AsyncData(value: HomeFollowing()) => _Message(
        text: l10n.homeAlreadyDebtFree,
      ),
      AsyncData(value: HomeNoDebts()) => _Message(
        art: const EmptyLot(),
        text: l10n.homeNoDebts,
        action: l10n.homeAddFirstDebt,
        onAction: () => context.push(Routes.newDebt),
      ),
      AsyncData(value: HomeShortfall(:final shortfall)) => _Message(
        text: l10n.budgetShortfall(
          formatMoney(shortfall, ref.watch(formatLocaleProvider)),
        ),
        action: l10n.changeBudget,
        onAction: () => context.push(Routes.settings),
      ),
      AsyncData(value: HomeAllCleared()) => const _AllCleared(),
      AsyncData(value: HomeFollowedUnavailable(:final strategyId)) => _Message(
        text: l10n.homeFollowedUnavailable(strategyName(l10n, strategyId)),
        action: l10n.homeChooseAnotherPlan,
        onAction: () => showFollowSheet(context),
      ),
      AsyncData(value: HomeNeverClears()) => _Message(
        text: l10n.homeNeverClears,
        action: l10n.changeBudget,
        onAction: () => context.push(Routes.settings),
      ),
      AsyncError() => ErrorRetryView(
        onRetry: () => ref
          ..invalidate(settingsControllerProvider)
          ..invalidate(currentPlansProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTooltip,
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    this.action,
    this.onAction,
    this.outlined = false,
    this.art,
  });

  /// A picture above the message.
  final Widget? art;

  final String text;
  final String? action;
  final VoidCallback? onAction;

  /// Use an outlined button (the hero already says the most).
  final bool outlined;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      if (art case final art?) ...[art, const SizedBox(height: 12)],
      HiVisBlock(
        child: Text(text, style: const TextStyle(fontSize: 17, height: 1.35)),
      ),
      if (action != null) ...[
        const SizedBox(height: 12),
        if (outlined)
          OutlinedButton(onPressed: onAction, child: Text(action!))
        else
          FilledButton(onPressed: onAction, child: Text(action!)),
      ],
    ],
  );
}

class _Following extends ConsumerWidget {
  const _Following({required this.result, required this.baseline});

  final Feasible result;
  final PayoffResult baseline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final locale = ref.watch(formatLocaleProvider);
    final now = ref.watch(clockProvider)();
    final plan = result.plan;
    final listOrder = [
      for (final d in ref.watch(debtsProvider).value ?? const <Debt>[]) d.id,
    ];
    String nameOf(PlanDebt d) => planDebtName(l10n, d);
    DateTime monthsAhead(int months) => DateTime(now.year, now.month + months);
    final debtFree = monthsAhead(plan.monthsToClear);
    final totals = totalOwedSeries(plan);
    final strategy = strategyName(l10n, result.strategyId);
    final summary = ref.watch(progressSummaryProvider).value;

    final lines = [
      ChartLine(values: totals, color: c.ink, width: 3),
      if (baseline case Feasible(plan: final minimums))
        ChartLine(
          values: totalOwedSeries(minimums)
              .take(plan.monthsToClear + 13)
              .toList(),
          color: c.faint,
          style: LineStyle.dashed,
          width: 2,
        ),
    ];
    final next = milestones(plan, nameOf).firstOrNull;
    final payments = firstMonthPayments(plan, nameOf);

    Widget key(Widget swatch, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch,
        const SizedBox(width: 6),
        Flexible(
          child: Text(label, style: TextStyle(fontSize: 12, color: c.ink2)),
        ),
      ],
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // The wall stands under the ring, on the hero's floor, when
            // there's room (spec §4.2).
            final wall =
                constraints.maxWidth >= 340 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.5;
            return HiVisBlock(
              child: Stack(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (wall)
                        SizedBox(
                          width: _wallWidth,
                          // Tall enough that the wall never meets the ring.
                          height: 84 + 8 + _wallWidth / 1.7,
                          child: summary == null
                              ? null
                              : Align(
                                  alignment: Alignment.topCenter,
                                  child: ProgressRing(
                                    percent: summary.paid.percent,
                                  ),
                                ),
                        )
                      else if (summary != null)
                        ProgressRing(percent: summary.paid.percent),
                      if (wall || summary != null) const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.homeDebtFreeBy,
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                DateFormat.MMM(locale).format(debtFree),
                                debtFree.year,
                              ].join('\n'),
                              style: displayStyle(
                                50,
                                color: c.onHiVis,
                              ).copyWith(height: 0.92),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.homeInDurationOnly(
                                formatDuration(l10n, plan.monthsToClear),
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                            if (summary != null &&
                                summary.paid.since != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                summary.paid.amount.isNegative
                                    ? l10n.homeOwesMore(
                                        formatMoney(
                                          Money(
                                            -summary.paid.amount.minor,
                                            summary.paid.amount.currency,
                                          ),
                                          locale,
                                        ),
                                      )
                                    : l10n.homePaidOff(
                                        formatMoney(
                                          summary.paid.amount,
                                          locale,
                                        ),
                                        DateFormat.MMMM(locale)
                                            .format(summary.paid.since!),
                                      ),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              StandingChip(standing: summary.standing),
                            ],
                            TextButton(
                              onPressed: () => showFollowSheet(context),
                              style: TextButton.styleFrom(
                                foregroundColor: c.onHiVis,
                                padding: EdgeInsets.zero,
                                alignment: Alignment.centerLeft,
                              ),
                              child: Text(l10n.homeFollowing(strategy)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (wall)
                    Positioned(
                      left: 0,
                      bottom: 0,
                      width: _wallWidth,
                      child: BrickWall(percent: summary?.paid.percent ?? 0),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        if (summary?.chart case final chart?)
          ProgressChartCard(
            chart: chart,
            debtFree: debtFree,
            trailing: strategy,
            onTap: () =>
                context.go(Routes.plan(result.strategyId, current: true)),
          )
        else
          InkWell(
            onTap: () =>
                context.go(Routes.plan(result.strategyId, current: true)),
            borderRadius: BorderRadius.circular(6),
            child: OutlinedCard(
              title: l10n.homeProjectionTitle,
              trailing: strategy,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BalanceLineChart(
                    lines: lines,
                    semanticLabel: l10n.homeProjectionLabel(
                      formatMoney(
                        plan.debts.fold(
                          Money.zero(plan.totalPaid.currency),
                          (s, d) => s + d.startingBalance,
                        ),
                        locale,
                      ),
                      DateFormat.yMMMM(locale).format(debtFree),
                    ),
                    startLabel: DateFormat.yMMM(locale).format(now),
                    // The minimums line runs on past debt-free.
                    endLabel: DateFormat.yMMM(locale).format(
                      monthsAhead(
                        lines
                            .map((l) => l.values.length - 1)
                            .reduce((a, b) => a > b ? a : b),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      key(
                        Container(width: 16, height: 3, color: c.ink),
                        strategy,
                      ),
                      if (lines.length > 1)
                        key(
                          Container(
                            width: 16,
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: c.faint, width: 2),
                              ),
                            ),
                          ),
                          l10n.homeMinimumsLine,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (summary != null) ...[
          const SizedBox(height: 12),
          CheckInCard(lastCheckIn: summary.lastCheckIn),
        ],
        if (next != null) ...[
          const SizedBox(height: 12),
          OutlinedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.homeNextUp(next.debt.name),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      DateFormat.yMMM(locale).format(monthsAhead(next.month)),
                      style: TextStyle(fontSize: 13, color: c.ink2),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Paid off that debt since the latest starting point.
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.outline, width: 2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _progressOn(next.debt.id, ref),
                    child: const CustomPaint(painter: HazardPainter()),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  next.next == null
                      ? l10n.homeNextUpLast(formatDuration(l10n, next.month))
                      : l10n.homeNextUpDetail(
                          formatDuration(l10n, next.month),
                          formatMoney(next.rollsOn, locale),
                          next.next!.name,
                        ),
                  style: TextStyle(fontSize: 12.5, color: c.ink2),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedCard(
          title: l10n.payThisMonth,
          trailing: formatMoney(
            payments.fold(
              Money.zero(plan.totalPaid.currency),
              (s, p) => s + p.amount,
            ),
            locale,
          ),
          child: Column(
            children: [
              for (final p in payments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: debtColor(c, p.debt.id, listOrder),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(p.debt.name)),
                      Text(
                        formatMoney(p.amount, locale),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The hero wall's width (it's 1.7 times as wide as tall).
const _wallWidth = 100.0;

/// How much of [debtId] is paid since the latest starting point, as the
/// hazard bar's fill (never less than a sliver).
double _progressOn(String debtId, WidgetRef ref) {
  final history = ref.watch(progressHistoryProvider).value;
  final start = history?.latestStart;
  final debts = ref.watch(debtsProvider).value ?? const <Debt>[];
  if (history == null || start == null) return 0.04;
  final from = history.checkInFor(start).balances[debtId]?.balance.minor;
  final now = debts.where((d) => d.id == debtId).firstOrNull?.balance.minor;
  if (from == null || now == null || from <= 0) return 0.04;
  return ((from - now) / from).clamp(0.04, 1.0);
}

class _AllCleared extends ConsumerWidget {
  const _AllCleared();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final summary = ref.watch(progressSummaryProvider).value;
    final amount = summary == null
        ? ''
        : formatMoney(summary.paid.amount, ref.watch(formatLocaleProvider));
    return _Message(
      art: const ClearedPlot(),
      text: l10n.homeAllCleared(amount),
      action: l10n.homeAddADebt,
      onAction: () => context.push(Routes.newDebt),
      outlined: true,
    );
  }
}
