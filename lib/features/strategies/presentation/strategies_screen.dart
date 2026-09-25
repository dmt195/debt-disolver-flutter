import 'dart:async';

import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/ads/presentation/ad_banner.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenario_name_dialog.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/domain/extra_payment.dart';
import 'package:debt_destroyer/features/strategies/domain/savings.dart';
import 'package:debt_destroyer/features/strategies/domain/strategy_groups.dart';
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
    final active = ref.watch(activeScenarioProvider);

    final Widget body;
    if (debts != null && debts.isEmpty) {
      body = _Message(l10n.strategiesEmpty);
    } else {
      body = switch ((plans, active)) {
        (
          AsyncData(:final value),
          AsyncData(value: final ActiveScenario scenario),
        ) =>
          ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const _ScenarioPicker(),
              _PayMoreSlider(budget: scenario.monthlyBudget),
              _SaveAsScenarioButton(active: scenario),
              _BaselineLine(value.baseline),
              ..._strategySections(context, value, scenario.parameters),
            ],
          ),
        (AsyncError(), _) => _Message(
          l10n.plansError,
          // Plans depend on settings, which may be what failed.
          onRetry: () => ref
            ..invalidate(settingsControllerProvider)
            ..invalidate(activeScenarioProvider)
            ..invalidate(plansProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.strategiesTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: l10n.scenariosTitle,
            onPressed: () => context.push(Routes.scenarios),
          ),
        ],
      ),
      body: body,
      bottomNavigationBar: const AdBanner(),
    );
  }
}

/// Ways to pay off, then the borrowing alternatives under their own
/// heading and caveat. Only a way to pay off can be marked cheapest.
List<Widget> _strategySections(
  BuildContext context,
  PlanSet plans,
  StrategyParameters parameters,
) {
  final l10n = context.l10n;
  final cheapest = bestPayOffMethod(plans.ranked)?.strategyId;
  Widget card(PayoffResult result) => _StrategyCard(
    result: result,
    baseline: plans.baseline,
    parameters: parameters,
    cheapest: result.strategyId == cheapest,
  );
  final alternatives = [
    for (final r in plans.ranked)
      if (isBorrowingAlternative(r.strategyId)) r,
  ];
  return [
    _SectionHeading(l10n.payOffMethodsHeading),
    for (final r in plans.ranked)
      if (!isBorrowingAlternative(r.strategyId)) card(r),
    if (alternatives.isNotEmpty) ...[
      _SectionHeading(l10n.alternativesHeading, note: l10n.alternativesNote),
      for (final r in alternatives) card(r),
    ],
  ];
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title, {this.note});

  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(note!, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
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
              if (strategyNickname(l10n, id) case final nickname?)
                Text(
                  nickname,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              Text(
                strategyDescription(l10n, id, parameters, locale),
                style: theme.textTheme.bodySmall,
              ),
              if (strategyBestFor(l10n, id) case final bestFor?)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    bestFor,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
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

class _FeasibleDetails extends ConsumerWidget {
  const _FeasibleDetails({
    required this.plan,
    required this.baseline,
    required this.locale,
  });

  final PayoffPlan plan;
  final PayoffResult baseline;
  final String locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                onPressed: () {
                  final id = ref.read(activeScenarioProvider).value?.id;
                  unawaited(
                    context.push(
                      id == null ? Routes.settings : Routes.editScenario(id),
                    ),
                  );
                },
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
    final committed = effectiveExtraMinor(
      ref.watch(extraPaymentProvider),
      widget.budget,
    );
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

/// Current, then each saved scenario. Hidden until something is saved.
class _ScenarioPicker extends ConsumerWidget {
  const _ScenarioPicker();

  /// Stands for Current in the menu: a null item value would read as "no
  /// selection". Scenario ids are UUIDs, so it can't clash.
  static const _current = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final saved = ref.watch(scenariosProvider).value ?? const <Scenario>[];
    if (saved.isEmpty) return const SizedBox.shrink();
    final selected = ref.watch(selectedScenarioIdProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: DropdownButton<String>(
        key: const ValueKey('scenario'),
        isExpanded: true,
        // A selection that was just deleted shows as Current.
        value: saved.any((s) => s.id == selected) ? selected : _current,
        items: [
          DropdownMenuItem(value: _current, child: Text(l10n.scenarioCurrent)),
          for (final s in saved)
            DropdownMenuItem(value: s.id, child: Text(s.name)),
        ],
        onChanged: (id) => ref
            .read(selectedScenarioIdProvider.notifier)
            .select(id == null || id == _current ? null : id),
      ),
    );
  }
}

/// Saves the scenario being viewed (plus any extra from the slider) under a
/// new name, then switches to it.
class _SaveAsScenarioButton extends ConsumerWidget {
  const _SaveAsScenarioButton({required this.active});

  final ActiveScenario active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final extra = effectiveExtraMinor(
      ref.watch(extraPaymentProvider),
      active.monthlyBudget,
    );
    // A saved scenario with nothing added would only be a copy of itself.
    if (active.id != null && extra == 0) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.bookmark_add_outlined),
        label: Text(l10n.saveAsScenario),
        onPressed: () => _save(context, ref, extra),
      ),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref, int extra) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final budget =
        active.monthlyBudget + Money(extra, active.monthlyBudget.currency);
    Scenario? created;
    final saved = await showScenarioNameDialog(
      context,
      title: l10n.saveAsScenario,
      submit: (name) async {
        final outcome = await ref
            .read(scenarioActionsProvider.notifier)
            .create(
              name: name,
              monthlyBudget: budget,
              parameters: active.parameters,
            );
        if (outcome case ScenarioSaved(:final scenario)) created = scenario;
        return scenarioOutcomeMessage(l10n, outcome);
      },
    );
    if (!saved || created == null) return;
    ref.read(selectedScenarioIdProvider.notifier).select(created!.id);
    messenger.showSnackBar(SnackBar(content: Text(l10n.scenarioSaved)));
  }
}
