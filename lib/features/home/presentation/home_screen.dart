import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/charts/balance_line_chart.dart';
import 'package:debt_destroyer/core/charts/hazard.dart';
import 'package:debt_destroyer/core/debt_colors.dart';
import 'package:debt_destroyer/core/error_view.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/core/widgets/hi_vis_block.dart';
import 'package:debt_destroyer/core/widgets/outlined_card.dart';
import 'package:debt_destroyer/features/analysis/domain/plan_series.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
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
  const _Message({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      HiVisBlock(
        child: Text(text, style: const TextStyle(fontSize: 17, height: 1.35)),
      ),
      if (action != null) ...[
        const SizedBox(height: 12),
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
        HiVisBlock(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.homeDebtFreeBy, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              Text(
                '${DateFormat.MMM(locale).format(debtFree)}\n${debtFree.year}',
                style: displayStyle(
                  50,
                  color: c.onHiVis,
                ).copyWith(height: 0.92),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.homeInDuration(
                  formatDuration(l10n, plan.monthsToClear),
                  strategy,
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => context.go(Routes.plan(result.strategyId)),
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
                  endLabel: DateFormat.yMMM(locale).format(debtFree),
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
                // Progress comes with check-ins (Plan 8); until then, a sliver.
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.outline, width: 2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.04,
                    child: CustomPaint(painter: HazardPainter()),
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
