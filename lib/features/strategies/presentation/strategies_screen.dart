import 'dart:async';

import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/charts/balance_line_chart.dart';
import 'package:debt_destroyer/core/charts/line_swatch.dart';
import 'package:debt_destroyer/core/illustrations/scenes.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/core/widgets/cheapest_badge.dart';
import 'package:debt_destroyer/core/widgets/hi_vis_block.dart';
import 'package:debt_destroyer/core/widgets/outlined_card.dart';
import 'package:debt_destroyer/features/ads/presentation/ad_banner.dart';
import 'package:debt_destroyer/features/analysis/domain/plan_series.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenario_name_dialog.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/domain/extra_payment.dart';
import 'package:debt_destroyer/features/strategies/domain/savings.dart';
import 'package:debt_destroyer/features/strategies/domain/strategy_groups.dart';
import 'package:debt_destroyer/features/strategies/presentation/current_plans.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
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
      body = _Message(l10n.strategiesEmpty, art: const EmptyLot());
    } else {
      body = switch ((plans, active)) {
        (
          AsyncData(:final value),
          AsyncData(value: final ActiveScenario scenario),
        ) =>
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              const _ScenarioPicker(),
              _RaceCard(value),
              const SizedBox(height: 12),
              HiVisBlock(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PayMoreSlider(budget: scenario.monthlyBudget),
                    _PayMoreEffect(plans: value, active: scenario),
                  ],
                ),
              ),
              _SaveAsScenarioButton(active: scenario),
              ..._strategySections(
                context,
                value,
                scenario.parameters,
                followed: ref
                    .watch(settingsControllerProvider)
                    .value
                    ?.followedStrategy,
              ),
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
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTooltip,
            onPressed: () => context.push(Routes.settings),
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
  StrategyParameters parameters, {
  StrategyId? followed,
}) {
  final l10n = context.l10n;
  final cheapest = bestPayOffMethod(plans.ranked)?.strategyId;
  // Until the user chooses, Home follows the cheapest.
  final following = followed ?? cheapest;
  final payOff = [
    for (final r in plans.ranked)
      if (!isBorrowingAlternative(r.strategyId)) r,
  ];
  final alternatives = [
    for (final r in plans.ranked)
      if (isBorrowingAlternative(r.strategyId)) r,
  ];
  final maxInterest = [
    for (final r in plans.ranked)
      if (r case Feasible(:final plan)) plan.totalInterest.minor,
  ].fold<int>(0, (m, v) => v > m ? v : m);
  final race = raceStrategies(plans);
  Widget card(PayoffResult result, {int? rank}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: _StrategyCard(
      result: result,
      baseline: plans.baseline,
      parameters: parameters,
      cheapest: result.strategyId == cheapest,
      following: result.strategyId == following,
      rank: rank,
      raceIndex: race.indexOf(result.strategyId),
      maxInterest: maxInterest,
    ),
  );
  return [
    _SectionHeading(l10n.payOffMethodsHeading),
    for (final (i, r) in payOff.indexed) card(r, rank: i + 1),
    _BaselineLine(plans.baseline),
    if (alternatives.isNotEmpty)
      _Alternatives(children: [for (final r in alternatives) card(r)]),
  ];
}

/// The strategies drawn on the race chart, in order: every feasible way to
/// pay off (never a borrowing alternative).
List<StrategyId> raceStrategies(PlanSet plans) => [
  for (final r in plans.ranked)
    if (r is Feasible && !isBorrowingAlternative(r.strategyId)) r.strategyId,
];

/// Line style for the [i]th raced strategy: solid, dashed, dotted, then
/// solid again, so no two neighbours rely on colour alone.
LineStyle raceStyle(int i) =>
    const [LineStyle.solid, LineStyle.dashed, LineStyle.dotted][i % 3];

/// Total owed over time for each way to pay off, plus minimums only.
class _RaceCard extends ConsumerWidget {
  const _RaceCard(this.plans);

  final PlanSet plans;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final locale = ref.watch(formatLocaleProvider);
    final now = ref.watch(clockProvider)();
    final raced = [
      for (final id in raceStrategies(plans))
        plans.ranked.firstWhere((r) => r.strategyId == id) as Feasible,
    ];
    if (raced.isEmpty) return const SizedBox.shrink();
    final longest = raced.fold<int>(
      0,
      (m, r) => r.plan.monthsToClear > m ? r.plan.monthsToClear : m,
    );
    final lines = [
      for (final (i, r) in raced.indexed)
        ChartLine(
          values: totalOwedSeries(r.plan),
          color: c.series[i % c.series.length],
          style: raceStyle(i),
          width: i == 0 ? 3 : 2.5,
          label: strategyName(l10n, r.strategyId),
        ),
      if (plans.baseline case Feasible(:final plan))
        ChartLine(
          values: totalOwedSeries(plan).take(longest + 13).toList(),
          color: c.faint,
          style: LineStyle.dashed,
          width: 2,
          label: l10n.raceMinimums,
        ),
    ];
    String month(int months) =>
        DateFormat.yMMM(locale).format(DateTime(now.year, now.month + months));
    final summary = [
      for (final r in raced)
        '${strategyName(l10n, r.strategyId)}: ${month(r.plan.monthsToClear)}',
    ].join('; ');
    Widget swatch(ChartLine line) =>
        LineSwatch(color: line.color, style: line.style);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: OutlinedCard(
        title: l10n.raceTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BalanceLineChart(
              lines: lines,
              semanticLabel: l10n.raceLabel(summary),
              startLabel: month(0),
              // The minimums line runs on past the slowest plan.
              endLabel: month(
                lines
                    .map((l) => l.values.length - 1)
                    .reduce((a, b) => a > b ? a : b),
              ),
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
                      swatch(line),
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
          ],
        ),
      ),
    );
  }
}

/// Borrowing alternatives: collapsed until asked for, with their caveat.
class _Alternatives extends StatefulWidget {
  const _Alternatives({required this.children});

  final List<Widget> children;

  @override
  State<_Alternatives> createState() => _AlternativesState();
}

class _AlternativesState extends State<_Alternatives> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(l10n.alternativesHeading, note: l10n.alternativesNote),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _open = !_open),
            icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
            label: Text(_open ? l10n.alternativesHide : l10n.alternativesShow),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface,
            ),
          ),
        ),
        if (_open) ...widget.children,
      ],
    );
  }
}

/// "3 months sooner, £190 less interest": what the slider's extra changes,
/// against the same settings with no extra. Only for Current, whose
/// no-extra plans Home already calculates.
class _PayMoreEffect extends ConsumerWidget {
  const _PayMoreEffect({required this.plans, required this.active});

  final PlanSet plans;
  final ActiveScenario active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final extra = effectiveExtraMinor(
      ref.watch(extraPaymentProvider),
      active.monthlyBudget,
    );
    if (active.id != null || extra <= 0) return const SizedBox.shrink();
    final before = ref.watch(currentPlansProvider).value;
    final now = bestPayOffMethod(plans.ranked);
    final was = before == null ? null : bestPayOffMethod(before.ranked);
    if (now == null || was == null) return const SizedBox.shrink();
    final months = was.plan.monthsToClear - now.plan.monthsToClear;
    final interest = was.plan.totalInterest - now.plan.totalInterest;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        l10n.payMoreEffect(
          formatDuration(l10n, months < 0 ? 0 : months),
          formatMoney(
            interest.isNegative ? Money.zero(interest.currency) : interest,
            locale,
          ),
        ),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
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
  const _Message(this.text, {this.onRetry, this.art});

  final String text;
  final Widget? art;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (art case final art?) ...[art, const SizedBox(height: 12)],
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
    required this.maxInterest,
    this.following = false,
    this.rank,
    this.raceIndex = -1,
  });

  final PayoffResult result;
  final PayoffResult baseline;
  final StrategyParameters parameters;
  final bool cheapest;

  /// The plan Home follows.
  final bool following;

  /// Position among the ways to pay off (1 first); null for alternatives.
  final int? rank;

  /// Index of this strategy's line on the race chart, or -1 if not drawn.
  final int raceIndex;

  /// The most interest any feasible plan pays, for the interest bar.
  final int maxInterest;

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

    final c = context.colors;
    final plan = switch (result) {
      Feasible(:final plan) when plan.monthsToClear > 0 => plan,
      _ => null,
    };
    return Card(
      key: ValueKey(id),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: result is Feasible ? () => context.push(Routes.plan(id)) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (rank != null) ...[
                    Text('$rank', style: displayStyle(30, color: c.ink)),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      strategyName(l10n, id),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (plan != null && raceIndex >= 0)
                    SizedBox(
                      width: 84,
                      child: BalanceLineChart(
                        compact: true,
                        height: 34,
                        semanticLabel: '',
                        lines: [
                          ChartLine(
                            values: totalOwedSeries(plan),
                            color: c.series[raceIndex % c.series.length],
                            style: raceStyle(raceIndex),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (cheapest || following)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (cheapest) const CheapestBadge(),
                      if (following)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: c.ink,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.following,
                            style: TextStyle(
                              color: c.ground,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (strategyNickname(l10n, id) case final nickname?)
                Text(
                  nickname,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: context.colors.ink,
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
              if (plan != null && maxInterest > 0) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: plan.totalInterest.minor / maxInterest,
                    minHeight: 6,
                    color: c.ink2,
                    backgroundColor: c.track,
                  ),
                ),
              ],
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
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (plan.change case CardTransferChange(:final moves, :final fee))
          Text(
            l10n.cardMovesSummary(moves.length, formatMoney(fee, locale)),
            style: Theme.of(context).textTheme.bodySmall,
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
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.payMore(formatMoney(extra, locale)),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: c.onHiVis,
            inactiveTrackColor: c.onHiVis.withValues(alpha: 0.25),
            thumbColor: Colors.white,
            overlayColor: c.onHiVis.withValues(alpha: 0.12),
            valueIndicatorColor: c.onHiVis,
            thumbShape: const _OutlinedThumb(),
            trackHeight: 6,
          ),
          child: Slider(
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
        ),
        Text(
          l10n.payMoreTotal(formatMoney(widget.budget + extra, locale)),
          style: const TextStyle(fontSize: 12.5),
        ),
      ],
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

/// A white slider thumb with a navy ring, as on the hi-vis block.
class _OutlinedThumb extends SliderComponentShape {
  const _OutlinedThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(24);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    context.canvas
      ..drawCircle(center, 11, Paint()..color = Colors.white)
      ..drawCircle(
        center,
        11,
        Paint()
          ..color = sliderTheme.activeTrackColor!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
  }
}
