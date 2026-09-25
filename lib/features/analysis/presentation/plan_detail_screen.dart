import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/charts/hazard.dart';
import 'package:debt_destroyer/core/charts/segment_bar.dart';
import 'package:debt_destroyer/core/charts/stacked_balance_chart.dart';
import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/core/debt_colors.dart';
import 'package:debt_destroyer/core/debt_icons.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/core/widgets/hi_vis_block.dart';
import 'package:debt_destroyer/core/widgets/outlined_card.dart';
import 'package:debt_destroyer/features/analysis/data/plan_exporter.dart';
import 'package:debt_destroyer/features/analysis/domain/plan_series.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_change_lines.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_schedule_table.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/progress/presentation/follow_sheet.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/domain/extra_payment.dart';
import 'package:debt_destroyer/features/strategies/domain/savings.dart';
import 'package:debt_destroyer/features/strategies/domain/strategy_groups.dart';
import 'package:debt_destroyer/features/strategies/presentation/current_plans.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:payoff_engine/payoff_engine.dart';

class PlanDetailScreen extends ConsumerWidget {
  const PlanDetailScreen({
    required this.strategyId,
    this.current = false,
    super.key,
  });

  final StrategyId strategyId;

  /// Show the plan on Current settings, without the selected scenario or
  /// the slider's extra (as Home follows it).
  final bool current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final title = Text(strategyName(l10n, strategyId));
    final result = current
        ? ref.watch(currentPlanProvider(strategyId))
        : ref.watch(planProvider(strategyId));
    return switch (result) {
      AsyncData(value: Feasible(:final plan)) when plan.monthsToClear > 0 =>
        _PlanPage(
          title: title,
          plan: plan,
          strategyId: strategyId,
          current: current,
        ),
      AsyncData() || AsyncError() => Scaffold(
        appBar: AppBar(title: title),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l10n.planUnavailable, textAlign: TextAlign.center),
          ),
        ),
      ),
      _ => Scaffold(
        appBar: AppBar(title: title),
        body: const Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

class _PlanPage extends ConsumerStatefulWidget {
  const _PlanPage({
    required this.title,
    required this.plan,
    required this.strategyId,
    required this.current,
  });

  final Widget title;
  final PayoffPlan plan;
  final StrategyId strategyId;
  final bool current;

  @override
  ConsumerState<_PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends ConsumerState<_PlanPage> {
  /// Debts (user ids) hidden from the chart by their legend chips.
  final _hidden = <String>{};
  var _showAllMonths = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final plan = widget.plan;
    final strategyId = widget.strategyId;
    final title = widget.title;
    final locale = ref.watch(formatLocaleProvider);
    final now = ref.watch(clockProvider)();
    final activeScenario = widget.current
        ? null
        : ref.watch(activeScenarioProvider).value;
    final scenarioName = activeScenario?.name;
    final nickname = strategyNickname(l10n, strategyId);
    final extraLine = activeScenario == null
        ? null
        : _extraLine(
            l10n,
            activeScenario,
            ref.watch(extraPaymentProvider),
            locale,
          );
    final changeLines = plan.change == null
        ? const <String>[]
        : planChangeLines(l10n, plan.change!, locale, now: now);
    final table = scheduleTableFor(
      l10n,
      plan,
      notes: [
        l10n.planScenario(scenarioName ?? l10n.scenarioCurrent),
        ?extraLine,
        ...changeLines,
      ],
    );
    final baseline = widget.current
        ? ref.watch(currentPlansProvider).value?.baseline
        : ref.watch(plansProvider).value?.baseline;
    final debts = ref.watch(debtsProvider).value ?? const <Debt>[];
    return Scaffold(
      appBar: AppBar(
        title: nickname == null && scenarioName == null && extraLine == null
            ? title
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  if (nickname != null)
                    Text(
                      nickname,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  if (scenarioName != null)
                    Text(
                      l10n.planScenario(scenarioName),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  if (extraLine != null)
                    Text(
                      extraLine,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                ],
              ),
        actions: [_shareMenu(context, table)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _Hero(
            plan: plan,
            baseline: baseline,
            now: now,
            locale: locale,
            onFollow: _canFollow(activeScenario)
                ? () => showFollowConfirm(context, widget.strategyId)
                : null,
          ),
          const SizedBox(height: 14),
          _chartCard(context, plan, debts, now, locale),
          const SizedBox(height: 14),
          _Milestones(plan: plan, debts: debts, now: now, locale: locale),
          if (changeLines.isNotEmpty) ...[
            const SizedBox(height: 14),
            OutlinedCard(
              title: l10n.whatChanges,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in changeLines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(line),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          _MoneySplit(plan: plan, locale: locale),
          const SizedBox(height: 14),
          _PayThisMonth(plan: plan, debts: debts, locale: locale),
          const SizedBox(height: 14),
          OutlinedCard(
            title: l10n.fullSchedule,
            trailing: formatDuration(l10n, plan.monthsToClear),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlanScheduleTable(
                  table: table,
                  limit: _showAllMonths ? null : 3,
                ),
                if (!_showAllMonths && table.rows.length > 3)
                  TextButton(
                    onPressed: () => setState(() => _showAllMonths = true),
                    child: Text(l10n.scheduleShowAll(table.rows.length)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Follow this plan is offered for a way to pay off that isn't already
  /// followed, on Current settings (spec §4.6).
  bool _canFollow(ActiveScenario? active) {
    if (widget.strategyId == StrategyId.minimumsOnly) return false;
    if (!widget.current && active?.id != null) return false;
    final settings = ref.watch(settingsControllerProvider).value;
    final plans = ref.watch(currentPlansProvider).value;
    final followed =
        settings?.followedStrategy ??
        (plans == null ? null : bestPayOffMethod(plans.ranked)?.strategyId);
    return followed != null && followed != widget.strategyId;
  }

  Widget _shareMenu(BuildContext context, ScheduleTable table) {
    final l10n = context.l10n;
    return Builder(
      builder: (buttonContext) => PopupMenuButton<ExportFormat>(
        icon: const Icon(Icons.share_outlined),
        tooltip: l10n.share,
        onSelected: (format) => runGuarded(
          context,
          () => ref
              .read(planExporterProvider)
              .export(
                table,
                format,
                baseName: 'debt-plan-${widget.strategyId.name}',
                subject: strategyName(l10n, widget.strategyId),
                origin: _globalRect(buttonContext),
              ),
          failureMessage: l10n.exportFailed,
        ),
        itemBuilder: (context) => [
          PopupMenuItem(value: ExportFormat.csv, child: Text(l10n.exportCsv)),
          PopupMenuItem(value: ExportFormat.xlsx, child: Text(l10n.exportXlsx)),
        ],
      ),
    );
  }

  Widget _chartCard(
    BuildContext context,
    PayoffPlan plan,
    List<Debt> debts,
    DateTime now,
    String locale,
  ) {
    final l10n = context.l10n;
    final c = context.colors;
    final ids = [for (final d in debts) d.id];
    final groups = groupPlanDebts(plan, (d) => planDebtName(l10n, d));
    final hiddenColumns = {
      for (final g in groups)
        if (_hidden.contains(g.id)) ...g.columns,
    };
    final digits = currencyDecimalDigits(plan.totalPaid.currency);
    var scale = 1;
    for (var i = 0; i < digits; i++) {
      scale *= 10;
    }
    String money(double major) => formatMoney(
      Money((major * scale).round(), plan.totalPaid.currency),
      locale,
    );
    final order = [for (final g in groups) g.name].join(', ');
    return OutlinedCard(
      title: l10n.detailChartTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StackedBalanceChart(
            stacks: stackedBalances(plan),
            colors: [for (final d in plan.debts) debtColor(c, d.id, ids)],
            names: [for (final d in plan.debts) planDebtName(l10n, d)],
            hidden: hiddenColumns,
            semanticLabel: l10n.detailChartLabel(plan.monthsToClear, order),
            tooltip: (month, balances, total) => [
              l10n.detailTooltip(
                month,
                DateFormat.yMMM(locale)
                    .format(DateTime(now.year, now.month + month)),
                money(total),
              ),
              for (final b in groupedBalances(groups, balances))
                '${b.debt.name} ${money(b.amount)}',
            ].join('\n'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final g in groups)
                FilterChip(
                  label: Text(g.name),
                  selected: !_hidden.contains(g.id),
                  showCheckmark: false,
                  avatar: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: debtColor(c, g.id, ids),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  onSelected: (on) => setState(
                    () => on ? _hidden.remove(g.id) : _hidden.add(g.id),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.detailChartHint,
            style: TextStyle(fontSize: 12, color: c.ink2),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.plan,
    required this.baseline,
    required this.now,
    required this.locale,
    this.onFollow,
  });

  final PayoffPlan plan;
  final PayoffResult? baseline;
  final DateTime now;
  final String locale;

  /// Follow this plan, when it can be followed.
  final VoidCallback? onFollow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final saves = baseline == null ? null : savingsAgainst(plan, baseline!);
    Widget stat(String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: c.onHiVis, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: displayStyle(22, color: c.onHiVis)),
            ),
          ],
        ),
      ),
    );
    return HiVisBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.homeDebtFreeBy, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 4),
          Text(
            DateFormat.yMMMM(locale)
                .format(DateTime(now.year, now.month + plan.monthsToClear)),
            style: displayStyle(40, color: c.onHiVis).copyWith(height: 0.95),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              stat(l10n.detailStatMonths, '${plan.monthsToClear}'),
              const SizedBox(width: 8),
              stat(
                l10n.detailStatInterest,
                formatMoney(plan.totalInterest, locale),
              ),
              if (saves != null) ...[
                const SizedBox(width: 8),
                stat(l10n.detailStatSaves, formatMoney(saves.money, locale)),
              ],
            ],
          ),
          if (onFollow != null) ...[
            const SizedBox(height: 10),
            FilledButton(
              onPressed: onFollow,
              style: FilledButton.styleFrom(
                backgroundColor: c.onHiVis,
                foregroundColor: Colors.white,
              ),
              child: Text(l10n.followThisPlan),
            ),
          ],
        ],
      ),
    );
  }
}

class _Milestones extends StatelessWidget {
  const _Milestones({
    required this.plan,
    required this.debts,
    required this.now,
    required this.locale,
  });

  final PayoffPlan plan;
  final List<Debt> debts;
  final DateTime now;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final ids = [for (final d in debts) d.id];
    final list = milestones(plan, (d) => planDebtName(l10n, d));
    String when(int month) => l10n.milestoneWhen(
      DateFormat.yMMM(locale).format(DateTime(now.year, now.month + month)),
      month,
    );
    Widget row({
      required Widget badge,
      required String date,
      required Widget title,
      String? detail,
      bool last = false,
    }) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              badge,
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: c.ink2,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(date, style: TextStyle(fontSize: 12, color: c.ink2)),
                  title,
                  if (detail != null)
                    Text(detail, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    Widget square(Color color, Widget child, {Color? border}) => Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color,
        border: border == null ? null : Border.all(color: border, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
    return OutlinedCard(
      title: l10n.milestonesTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in list)
            row(
              badge: square(
                debtColor(c, m.debt.id, ids),
                Icon(_iconFor(m.debt.id), color: Colors.white, size: 19),
              ),
              date: when(m.month),
              title: Text(
                l10n.milestoneCleared(m.debt.name),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              detail: m.next == null
                  ? null
                  : l10n.milestoneRollsOn(
                      formatMoney(m.rollsOn, locale),
                      m.next!.name,
                    ),
            ),
          row(
            badge: square(
              c.hiVis,
              Icon(Icons.check, color: c.onHiVis, size: 20),
              border: c.onHiVis,
            ),
            date: when(plan.monthsToClear),
            title: Text(
              l10n.milestoneDebtFree,
              style: displayStyle(20, color: c.ink),
            ),
            detail: l10n.milestoneTotalPaid(
              formatMoney(plan.totalPaid, locale),
            ),
            last: true,
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String id) {
    for (final d in debts) {
      if (d.id == id) return debtTypeIcon(d.type);
    }
    return Icons.account_balance_outlined;
  }
}

class _MoneySplit extends StatelessWidget {
  const _MoneySplit({required this.plan, required this.locale});

  final PayoffPlan plan;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final split = moneySplit(plan);
    Widget key(Widget swatch, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 12, height: 12, child: swatch),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    );
    return OutlinedCard(
      title: l10n.moneySplitTitle(formatMoney(plan.totalPaid, locale)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentBar(
            height: 30,
            semanticLabel: [
              l10n.moneySplitDebts(formatMoney(split.principal, locale)),
              l10n.moneySplitInterest(formatMoney(split.interest, locale)),
              if (split.fees.isPositive)
                l10n.moneySplitFees(formatMoney(split.fees, locale)),
            ].join(', '),
            segments: [
              Segment(split.principal.minor.toDouble(), c.ink2),
              Segment(split.interest.minor.toDouble(), c.ink, hazard: true),
              if (split.fees.isPositive)
                Segment(split.fees.minor.toDouble(), c.today),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              key(
                ColoredBox(color: c.ink2),
                l10n.moneySplitDebts(formatMoney(split.principal, locale)),
              ),
              key(
                const CustomPaint(painter: HazardPainter(stripe: 3)),
                l10n.moneySplitInterest(formatMoney(split.interest, locale)),
              ),
              if (split.fees.isPositive)
                key(
                  ColoredBox(color: c.today),
                  l10n.moneySplitFees(formatMoney(split.fees, locale)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PayThisMonth extends StatelessWidget {
  const _PayThisMonth({
    required this.plan,
    required this.debts,
    required this.locale,
  });

  final PayoffPlan plan;
  final List<Debt> debts;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final ids = [for (final d in debts) d.id];
    final payments = firstMonthPayments(plan, (d) => planDebtName(l10n, d));
    final most = payments.fold<int>(
      0,
      (m, p) => p.amount.minor > m ? p.amount.minor : m,
    );
    final total = payments.fold(
      Money.zero(plan.totalPaid.currency),
      (s, p) => s + p.amount,
    );
    return OutlinedCard(
      title: l10n.payThisMonth,
      trailing: formatMoney(total, locale),
      child: Column(
        children: [
          for (final p in payments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(p.debt.name)),
                  Expanded(
                    flex: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: most == 0 ? 0 : p.amount.minor / most,
                        minHeight: 10,
                        color: debtColor(c, p.debt.id, ids),
                        backgroundColor: c.track,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
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
    );
  }
}

/// "Including £X a month extra (£Y a month in total)", or null when the
/// slider's effective extra is zero.
String? _extraLine(
  AppLocalizations l10n,
  ActiveScenario scenario,
  int storedExtra,
  String locale,
) {
  final extra = effectiveExtraMinor(storedExtra, scenario.monthlyBudget);
  if (extra <= 0) return null;
  final currency = scenario.monthlyBudget.currency;
  return l10n.planExtra(
    formatMoney(Money(extra, currency), locale),
    formatMoney(scenario.monthlyBudget + Money(extra, currency), locale),
  );
}

/// Where [context]'s widget is on screen, for anchoring the share sheet.
Rect? _globalRect(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The plan's schedule with translated column names.
ScheduleTable scheduleTableFor(
  AppLocalizations l10n,
  PayoffPlan plan, {
  List<String> notes = const [],
}) => buildScheduleTable(
  plan,
  debtNames: [for (final d in plan.debts) planDebtName(l10n, d)],
  labels: ScheduleLabels(
    month: l10n.scheduleMonth,
    payment: l10n.schedulePayment,
    balance: l10n.scheduleBalance,
    totalPayment: l10n.scheduleTotalPayment,
    totalBalance: l10n.scheduleTotalBalance,
  ),
  notes: notes,
);
