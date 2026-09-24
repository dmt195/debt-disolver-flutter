import 'dart:async';

import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/ads/presentation/ad_banner.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/domain/extra_payment.dart';
import 'package:debt_destroyer/features/strategies/domain/savings.dart';
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
    final settings = ref.watch(settingsControllerProvider).value;

    final Widget body;
    if (debts != null && debts.isEmpty) {
      body = _Message(l10n.strategiesEmpty);
    } else {
      body = switch ((plans, settings)) {
        (AsyncData(:final value), final AppSettings settings) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _PayMoreSlider(budget: settings.monthlyBudget),
            _BaselineLine(value.baseline),
            for (final (i, result) in value.ranked.indexed)
              _StrategyCard(
                result: result,
                baseline: value.baseline,
                parameters: settings.strategyParameters,
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
      bottomNavigationBar: const AdBanner(),
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

/// The minimums-only reference every strategy is measured against.
class _BaselineLine extends ConsumerWidget {
  const _BaselineLine(this.baseline);

  final PayoffResult baseline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final text = switch (baseline) {
      Feasible(:final plan) when plan.monthsToClear > 0 => l10n.baselineSummary(
        formatDuration(l10n, plan.monthsToClear),
        formatMoney(plan.totalInterest, locale),
      ),
      NeverClears() => l10n.baselineNeverClears,
      _ => null, // infeasible: every card already says so
    };
    if (text == null) return const SizedBox.shrink();
    final opens = baseline is Feasible;
    return ListTile(
      key: const ValueKey('baseline'),
      leading: const Icon(Icons.hourglass_bottom),
      title: Text(text),
      trailing: opens ? const Icon(Icons.chevron_right) : null,
      onTap: opens
          ? () => context.push(Routes.plan(StrategyId.minimumsOnly))
          : null,
    );
  }
}

class _StrategyCard extends ConsumerWidget {
  const _StrategyCard({
    required this.result,
    required this.baseline,
    required this.parameters,
    required this.cheapest,
  });

  final PayoffResult result;
  final PayoffResult baseline;
  final StrategyParameters parameters;
  final bool cheapest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final theme = Theme.of(context);
    final id = result.strategyId;

    final details = switch (result) {
      Feasible(:final plan) => _FeasibleDetails(
        plan: plan,
        baseline: baseline,
        locale: locale,
      ),
      Infeasible(:final shortfall, :final month) => Text(
        l10n.infeasible(formatMoney(shortfall, locale), month),
        style: TextStyle(color: theme.colorScheme.error),
      ),
      NeverClears() => Text(
        l10n.neverClears,
        style: TextStyle(color: theme.colorScheme.error),
      ),
      NotApplicable(:final reason) => Text(
        notApplicableReason(l10n, reason),
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
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
  const _FeasibleDetails({
    required this.plan,
    required this.baseline,
    required this.locale,
  });

  final PayoffPlan plan;
  final PayoffResult baseline;
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
        if (_savingsText(l10n) case final text?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        if (plan.change case TransferChange(
          limitAssumed: true,
          :final creditLimit,
        ))
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.transferLimitAssumed(formatMoney(creditLimit, locale)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () => context.push(Routes.settings),
                child: Text(l10n.setCreditLimit),
              ),
            ],
          ),
      ],
    );
  }

  String? _savingsText(AppLocalizations l10n) {
    if (baseline is NeverClears) return l10n.clearsUnlikeMinimums;
    final savings = savingsAgainst(plan, baseline);
    if (savings == null) return null;
    final amount = formatMoney(savings.money, locale);
    return savings.months > 0
        ? l10n.savesVersusMinimums(amount, formatDuration(l10n, savings.months))
        : l10n.savesMoneyVersusMinimums(amount);
  }
}

/// "Pay £X more a month": changes the budget every plan uses, recalculating
/// shortly after the thumb stops moving.
class _PayMoreSlider extends ConsumerStatefulWidget {
  const _PayMoreSlider({required this.budget});

  final Money budget;

  @override
  ConsumerState<_PayMoreSlider> createState() => _PayMoreSliderState();
}

class _PayMoreSliderState extends ConsumerState<_PayMoreSlider> {
  double? _dragging;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _commit(double value) =>
      ref.read(extraPaymentProvider.notifier).set(value.round());

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final step = extraPaymentStepMinor(widget.budget);
    final divisions = widget.budget.minor ~/ step;
    if (divisions < 1) return const SizedBox.shrink();
    final max = divisions * step;
    final committed = ref.watch(extraPaymentProvider).clamp(0, max);
    final value = _dragging ?? committed.toDouble();
    final extra = Money(value.round(), widget.budget.currency);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.payMore(formatMoney(extra, locale)),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Slider(
            key: const ValueKey('payMore'),
            value: value,
            max: max.toDouble(),
            divisions: divisions,
            label: formatMoney(extra, locale),
            onChanged: (v) {
              setState(() => _dragging = v);
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 250),
                () => _commit(v),
              );
            },
            onChangeEnd: (v) {
              _debounce?.cancel();
              _commit(v);
              setState(() => _dragging = null);
            },
          ),
          Text(
            l10n.payMoreTotal(formatMoney(widget.budget + extra, locale)),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
