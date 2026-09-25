import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/charts/comparison_bars.dart';
import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/core/error_view.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/illustrations/scenes.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/core/widgets/cheapest_badge.dart';
import 'package:debt_destroyer/core/widgets/outlined_card.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenario_comparison.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:payoff_engine/payoff_engine.dart';

/// Saved scenarios, and a side-by-side comparison. No ads here.
class ScenariosScreen extends StatelessWidget {
  const ScenariosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.scenariosTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.scenariosTabSaved),
              Tab(text: l10n.scenariosTabCompare),
            ],
          ),
        ),
        body: const TabBarView(children: [_SavedTab(), _CompareTab()]),
      ),
    );
  }
}

class _SavedTab extends ConsumerWidget {
  const _SavedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    return switch (ref.watch(scenariosProvider)) {
      AsyncData(:final value) when value.isEmpty => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Signpost(),
          const SizedBox(height: 12),
          Text(l10n.scenariosEmpty, textAlign: TextAlign.center),
        ],
      ),
      AsyncData(:final value) => ListView(
        children: [
          for (final s in value)
            ListTile(
              key: ValueKey(s.id),
              title: Text(s.name),
              subtitle: Text(
                l10n.scenarioBudget(formatMoney(s.monthlyBudget, locale)),
              ),
              onTap: () => context.push(Routes.editScenario(s.id)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: l10n.delete,
                onPressed: () => _confirmDelete(context, ref, s),
              ),
            ),
        ],
      ),
      AsyncError() => ErrorRetryView(
        onRetry: () => ref.invalidate(scenariosProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Scenario scenario,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteScenarioTitle(scenario.name)),
        content: Text(l10n.deleteDebtBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await runGuarded(
      context,
      () => ref.read(scenarioActionsProvider.notifier).delete(scenario.id),
    );
  }
}

class _CompareTab extends ConsumerWidget {
  const _CompareTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(scenarioComparisonProvider)) {
        AsyncData(:final value) => _CompareList(value),
        AsyncError() => ErrorRetryView(
          onRetry: () => ref.invalidate(scenarioComparisonProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
}

class _CompareList extends ConsumerWidget {
  const _CompareList(this.rows);

  final List<ScenarioComparison> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final theme = Theme.of(context);
    Money? cheapest;
    for (final row in rows) {
      final paid = row.best?.plan.totalPaid;
      if (paid != null && (cheapest == null || paid < cheapest)) {
        cheapest = paid;
      }
    }
    final c = context.colors;
    final now = ref.watch(clockProvider)();
    final digits = currencyDecimalDigits(
      rows
              .firstWhere((r) => r.best != null, orElse: () => rows.first)
              .best
              ?.plan
              .totalPaid
              .currency ??
          'GBP',
    );
    var scale = 1;
    for (var i = 0; i < digits; i++) {
      scale *= 10;
    }
    final bars = [
      for (final row in rows)
        ComparisonBar(
          label: row.name ?? l10n.scenarioCurrent,
          value: (row.best?.plan.totalInterest.minor ?? 0) / scale,
          trailing: switch (row.best) {
            final best? => DateFormat.yMMM(
              locale,
            ).format(DateTime(now.year, now.month + best.plan.monthsToClear)),
            null => l10n.compareNoPlan,
          },
          highlight: cheapest != null && row.best?.plan.totalPaid == cheapest,
        ),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        OutlinedCard(
          title: l10n.compareChartTitle,
          child: ComparisonBars(
            bars: bars,
            semanticLabel: l10n.compareChartLabel(
              [
                for (final (i, b) in bars.indexed)
                  '${b.label}: ${switch (rows[i].best) {
                    final best? => formatMoney(best.plan.totalInterest, locale),
                    null => l10n.compareNoPlan,
                  }}, ${b.trailing}',
              ].join('; '),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.compareChartKey,
          style: TextStyle(fontSize: 12, color: c.ink2),
        ),
        const SizedBox(height: 12),
        for (final row in rows)
          _row(
            context,
            l10n,
            locale,
            row,
            theme,
            isCheapest:
                cheapest != null && row.best?.plan.totalPaid == cheapest,
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    String locale,
    ScenarioComparison row,
    ThemeData theme, {
    required bool isCheapest,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      key: ValueKey('compare-${row.id ?? 'current'}'),
      child: ListTile(
        title: Text(row.name ?? l10n.scenarioCurrent),
        subtitle: Text(switch (row.best) {
          final best? when best.plan.monthsToClear == 0 => l10n.alreadyDebtFree,
          final best? => l10n.compareBest(
            strategyName(l10n, best.strategyId),
            formatDuration(l10n, best.plan.monthsToClear),
            formatMoney(best.plan.totalInterest, locale),
          ),
          null => l10n.compareNoPlan,
        }),
        trailing: isCheapest ? const CheapestBadge() : null,
      ),
    ),
  );
}
