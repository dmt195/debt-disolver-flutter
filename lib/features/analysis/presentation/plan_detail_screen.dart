import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/features/analysis/data/plan_exporter.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_chart_tab.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_schedule_tab.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_summary_tab.dart';
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
    final table = scheduleTableFor(l10n, plan);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: title,
          actions: [
            PopupMenuButton<ExportFormat>(
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
                    ),
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

/// The plan's schedule with translated column names.
ScheduleTable scheduleTableFor(AppLocalizations l10n, PayoffPlan plan) =>
    buildScheduleTable(
      plan,
      debtNames: [for (final d in plan.debts) planDebtName(l10n, d)],
      labels: ScheduleLabels(
        month: l10n.scheduleMonth,
        payment: l10n.schedulePayment,
        balance: l10n.scheduleBalance,
        totalPayment: l10n.scheduleTotalPayment,
        totalBalance: l10n.scheduleTotalBalance,
      ),
    );
