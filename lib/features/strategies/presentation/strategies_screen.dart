import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:payoff_engine/payoff_engine.dart';

class StrategiesScreen extends ConsumerWidget {
  const StrategiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final debts = ref.watch(debtsProvider).value;
    final plans = ref.watch(plansProvider);
    final parameters = ref
        .watch(settingsControllerProvider)
        .value
        ?.strategyParameters;

    final Widget body;
    if (debts != null && debts.isEmpty) {
      body = _Message(l10n.strategiesEmpty);
    } else {
      body = switch ((plans, parameters)) {
        (AsyncData(:final value), final StrategyParameters parameters) =>
          ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final (i, result) in value.indexed)
                _StrategyCard(
                  result: result,
                  parameters: parameters,
                  cheapest: i == 0 && result is Feasible,
                ),
            ],
          ),
        (AsyncError(), _) => _Message(
          l10n.plansError,
          // Plans depend on settings, which may be what failed.
          onRetry: () => ref
            ..invalidate(settingsControllerProvider)
            ..invalidate(plansProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.strategiesTitle)),
      body: body,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: Text(context.l10n.retry)),
          ],
        ],
      ),
    ),
  );
}

class _StrategyCard extends ConsumerWidget {
  const _StrategyCard({
    required this.result,
    required this.parameters,
    required this.cheapest,
  });

  final PayoffResult result;
  final StrategyParameters parameters;
  final bool cheapest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final theme = Theme.of(context);
    final id = result.strategyId;

    final details = switch (result) {
      Feasible(:final plan) => _FeasibleDetails(plan: plan, locale: locale),
      Infeasible(:final shortfall, :final month) => Text(
        l10n.infeasible(formatMoney(shortfall, locale), month),
        style: TextStyle(color: theme.colorScheme.error),
      ),
      NeverClears() => Text(
        l10n.neverClears,
        style: TextStyle(color: theme.colorScheme.error),
      ),
    };

    return Card(
      key: ValueKey(id),
      color: cheapest ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: result is Feasible ? () => context.push(Routes.plan(id)) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strategyName(l10n, id),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (cheapest) Chip(label: Text(l10n.cheapest)),
                ],
              ),
              Text(
                strategyDescription(l10n, id, parameters, locale),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              details,
            ],
          ),
        ),
      ),
    );
  }
}

class _FeasibleDetails extends StatelessWidget {
  const _FeasibleDetails({required this.plan, required this.locale});

  final PayoffPlan plan;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (plan.monthsToClear == 0) return Text(l10n.alreadyDebtFree);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.debtFreeIn(formatDuration(l10n, plan.monthsToClear)),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text(
          '${l10n.totalInterest}: ${formatMoney(plan.totalInterest, locale)}',
        ),
        if (plan.totalFees.isPositive)
          Text('${l10n.fees}: ${formatMoney(plan.totalFees, locale)}'),
        Text('${l10n.totalPaid}: ${formatMoney(plan.totalPaid, locale)}'),
      ],
    );
  }
}
