import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/analysis/data/plan_exporter.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_change_lines.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_chart_tab.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_schedule_tab.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_summary_tab.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:debt_destroyer/features/strategies/domain/extra_payment.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payoff_engine/payoff_engine.dart';

class PlanDetailScreen extends ConsumerWidget {
  const PlanDetailScreen({required this.strategyId, super.key});

  final StrategyId strategyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final title = Text(strategyName(l10n, strategyId));
    final result = ref.watch(planProvider(strategyId));
    return switch (result) {
      AsyncData(value: Feasible(:final plan)) when plan.monthsToClear > 0 =>
        _PlanTabs(title: title, plan: plan, strategyId: strategyId),
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

class _PlanTabs extends ConsumerWidget {
  const _PlanTabs({
    required this.title,
    required this.plan,
    required this.strategyId,
  });

  final Widget title;
  final PayoffPlan plan;
  final StrategyId strategyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final activeScenario = ref.watch(activeScenarioProvider).value;
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
    final table = scheduleTableFor(
      l10n,
      plan,
      notes: [
        l10n.planScenario(scenarioName ?? l10n.scenarioCurrent),
        ?extraLine,
        if (plan.change case final change?)
          ...planChangeLines(
            l10n,
            change,
            locale,
            now: ref.watch(clockProvider)(),
          ),
      ],
    );
    return DefaultTabController(
      length: 3,
      child: Scaffold(
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
          actions: [
            Builder(
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
                        baseName: 'debt-plan-${strategyId.name}',
                        subject: strategyName(l10n, strategyId),
                        origin: _globalRect(buttonContext),
                      ),
                  failureMessage: l10n.exportFailed,
                ),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: ExportFormat.csv,
                    child: Text(l10n.exportCsv),
                  ),
                  PopupMenuItem(
                    value: ExportFormat.xlsx,
                    child: Text(l10n.exportXlsx),
                  ),
                ],
              ),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.tabSummary),
              Tab(text: l10n.tabChart),
              Tab(text: l10n.tabSchedule),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            PlanSummaryTab(plan: plan),
            PlanChartTab(plan: plan),
            PlanScheduleTab(table: table),
          ],
        ),
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
