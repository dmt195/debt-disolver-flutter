import 'dart:async';

import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/charts/segment_bar.dart';
import 'package:debt_destroyer/core/charts/share_donut.dart';
import 'package:debt_destroyer/core/debt_colors.dart';
import 'package:debt_destroyer/core/debt_icons.dart';
import 'package:debt_destroyer/core/error_view.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/core/widgets/outlined_card.dart';
import 'package:debt_destroyer/features/ads/presentation/ad_banner.dart';
import 'package:debt_destroyer/features/analysis/domain/plan_series.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/presentation/current_plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:payoff_engine/payoff_engine.dart';

class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final debts = ref.watch(debtsProvider);
    final settingsState = ref.watch(settingsControllerProvider);
    final settings = settingsState.value;
    final hasDebts = debts.value?.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.debtsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTooltip,
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      // Actions sit above the banner, with a gap, so nothing tappable
      // touches the ad. One SafeArea covers both.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.push(Routes.newDebt),
                      // Icon and label wrap rather than overflow at large
                      // text sizes.
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add, size: 18),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              l10n.addDebt,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: hasDebts
                          ? () => context.go(Routes.plans)
                          : null,
                      child: Text(
                        l10n.compareStrategies,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: AdBanner(respectsSafeArea: false),
            ),
          ],
        ),
      ),
      body: switch ((debts, settings)) {
        _ when settingsState.hasError || debts.hasError => ErrorRetryView(
          // Debts depend on settings, so reload both.
          onRetry: () => ref
            ..invalidate(settingsControllerProvider)
            ..invalidate(debtsProvider),
        ),
        (AsyncData(:final value), final AppSettings settings) => _DebtsBody(
          debts: value,
          settings: settings,
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _DebtsBody extends ConsumerStatefulWidget {
  const _DebtsBody({required this.debts, required this.settings});

  final List<Debt> debts;
  final AppSettings settings;

  @override
  ConsumerState<_DebtsBody> createState() => _DebtsBodyState();
}

class _DebtsBodyState extends ConsumerState<_DebtsBody> {
  /// Debts swiped away but not yet gone from the stream. A dismissed
  /// Dismissible must leave the tree immediately.
  final _removed = <String>{};

  @override
  void didUpdateWidget(_DebtsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Forget deletions the stream has caught up with.
    _removed.retainWhere((id) => widget.debts.any((d) => d.id == id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final debts = [
      for (final d in widget.debts)
        if (!_removed.contains(d.id)) d,
    ];
    final currency = widget.settings.currencyCode;
    final minimums = totalMinimumPayments(debts, currency: currency);
    final budget = widget.settings.monthlyBudget;

    final home = ref.watch(homePlanProvider).value;
    final plan = home is HomeFollowing ? home.result.plan : null;
    final ids = [for (final d in debts) d.id];
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryCard(
            debts: debts,
            ids: ids,
            minimums: minimums,
            budget: budget,
            locale: locale,
          ),
          if (minimums > budget) ...[
            const SizedBox(height: 10),
            _ShortfallBanner(shortfall: minimums - budget, locale: locale),
          ],
        ],
      ),
    );

    if (debts.isEmpty) {
      return ListView(
        children: [
          header,
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l10n.debtsEmpty, textAlign: TextAlign.center),
          ),
        ],
      );
    }
    return ReorderableListView.builder(
      header: header,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: debts.length,
      onReorderItem: (from, to) => _reorder(debts, from, to),
      itemBuilder: (context, i) => Padding(
        key: ValueKey(debts[i].id),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: _dismissible(
          debts[i],
          locale,
          ids: ids,
          position: plan == null ? null : payoffPosition(plan, debts[i].id),
          share: _share(debts[i], debts),
        ),
      ),
    );
  }

  static double _share(Debt debt, List<Debt> debts) {
    final total = debts.fold<int>(0, (s, d) => s + d.balance.minor);
    return total == 0 ? 0 : debt.balance.minor / total;
  }

  Widget _dismissible(
    Debt debt,
    String locale, {
    required List<String> ids,
    required int? position,
    required double share,
  }) => Dismissible(
    key: ValueKey(debt.id),
    direction: DismissDirection.endToStart,
    background: ColoredBox(
      color: Theme.of(context).colorScheme.errorContainer,
      child: const Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Icon(Icons.delete_outline),
        ),
      ),
    ),
    confirmDismiss: (_) => _confirmDelete(debt),
    onDismissed: (_) {
      setState(() => _removed.add(debt.id));
      unawaited(_delete(debt));
    },
    child: DebtTile(
      debt: debt,
      locale: locale,
      colorIds: ids,
      position: position,
      share: share,
    ),
  );

  Future<bool> _confirmDelete(Debt debt) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteDebtTitle(debt.name)),
        content: Text(l10n.deleteDebtBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _delete(Debt debt) async {
    final deleted = await runGuarded(context, () async {
      await ref.read(debtActionsProvider.notifier).delete(debt.id);
      return true;
    });
    if (deleted != null) return;
    // Nothing was deleted, so show the debt again. Wait until the dismissed
    // tile has left the tree first, or Dismissible asserts.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) setState(() => _removed.remove(debt.id));
  }

  Future<void> _reorder(List<Debt> visible, int from, int to) async {
    final ids = reorderedIds(
      [for (final d in visible) d.id],
      from: from,
      to: to,
      hidden: [
        for (final d in widget.debts)
          if (_removed.contains(d.id)) d.id,
      ],
    );
    await runGuarded(
      context,
      () => ref.read(debtActionsProvider.notifier).reorder(ids),
    );
  }
}

/// The full id order after moving the debt at [from] to [to] among
/// [visibleIds] (`to` as adjusted by `onReorderItem`). Debts [hidden] while
/// their deletion is pending stay at the end, because the repository needs
/// every stored id.
@visibleForTesting
List<String> reorderedIds(
  List<String> visibleIds, {
  required int from,
  required int to,
  List<String> hidden = const [],
}) {
  final ids = [...visibleIds];
  ids.insert(to, ids.removeAt(from));
  return [...ids, ...hidden];
}

class DebtTile extends StatelessWidget {
  const DebtTile({
    required this.debt,
    required this.locale,
    this.colorIds = const [],
    this.position,
    this.share = 0,
    super.key,
  });

  final Debt debt;
  final String locale;

  /// The user's list order, which gives each debt its colour.
  final List<String> colorIds;

  /// Where the debt comes in the payoff order (1 first), if known.
  final int? position;

  /// This debt's share of everything owed, 0–1.
  final double share;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final color = debtColor(c, debt.id, colorIds);
    final heat = aprHeat(debt.aprBps);
    final heatLabel = switch (heat) {
      AprHeat.high => l10n.aprHeatHigh,
      AprHeat.medium => l10n.aprHeatMedium,
      AprHeat.low => l10n.aprHeatLow,
    };
    final details = [
      l10n.debtApr(formatPercent(debt.aprBps, locale)),
      l10n.debtMinimum(formatMoney(minimumPayment(debt), locale)),
      if (debt.transferOffer != null) l10n.debtTransferOffer,
    ].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.editDebt(debt.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  debtTypeIcon(debt.type),
                  color: Colors.white,
                  size: 21,
                  semanticLabel: debtTypeLabel(l10n, debt.type),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          debt.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        _HeatChip(label: heatLabel, high: heat == AprHeat.high),
                        Text(
                          formatMoney(debt.balance, locale),
                          style: displayStyle(18, color: c.ink),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: share,
                        minHeight: 6,
                        color: color,
                        backgroundColor: c.track,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      children: [
                        Text(
                          details,
                          style: TextStyle(fontSize: 12, color: c.ink2),
                        ),
                        if (position != null)
                          Text(
                            l10n.debtClearsPosition(ordinal(position!)),
                            style: TextStyle(fontSize: 12, color: c.ink2),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeatChip extends StatelessWidget {
  const _HeatChip({required this.label, required this.high});

  final String label;
  final bool high;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: high ? c.ink : null,
        border: high ? null : Border.all(color: c.ink2, width: 1.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: high ? c.ground : c.ink2,
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.debts,
    required this.ids,
    required this.minimums,
    required this.budget,
    required this.locale,
  });

  final List<Debt> debts;
  final List<String> ids;
  final Money minimums;
  final Money budget;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final total = debts.fold(
      Money.zero(budget.currency),
      (s, d) => s + d.balance,
    );
    final extra = budget - minimums;
    // Wraps the amount under its label when large text leaves no room.
    Widget figure(String label, Money value) => Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 8,
      children: [
        Text(label, style: const TextStyle(fontSize: 13.5)),
        Text(
          formatMoney(value, locale),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
    String percent(Debt d) => total.minor == 0
        ? '0%'
        : '${(d.balance.minor * 100 / total.minor).round()}%';
    return OutlinedCard(
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ShareDonut(
            slices: [
              for (final d in debts)
                (
                  value: d.balance.minor.toDouble(),
                  color: debtColor(c, d.id, ids),
                ),
            ],
            centre: formatMoney(total, locale),
            caption: l10n.debtsTotalCaption,
            semanticLabel: l10n.debtsShareLabel(
              [for (final d in debts) '${d.name} ${percent(d)}'].join(', '),
              formatMoney(total, locale),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 150, maxWidth: 170),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                figure(l10n.minimumPayments, minimums),
                const SizedBox(height: 6),
                figure(l10n.monthlyBudget, budget),
                const SizedBox(height: 8),
                SegmentBar(
                  semanticLabel: l10n.debtsExtraAtWork(
                    formatMoney(
                      extra.isPositive ? extra : Money.zero(budget.currency),
                      locale,
                    ),
                  ),
                  segments: [
                    Segment(minimums.minor.toDouble(), c.ink2),
                    if (extra.isPositive)
                      Segment(extra.minor.toDouble(), c.hiVis),
                  ],
                ),
                if (extra.isPositive) ...[
                  const SizedBox(height: 6),
                  Text(
                    l10n.debtsExtraAtWork(formatMoney(extra, locale)),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortfallBanner extends StatelessWidget {
  const _ShortfallBanner({required this.shortfall, required this.locale});

  final Money shortfall;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return OutlinedCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(l10n.budgetShortfall(formatMoney(shortfall, locale))),
          ),
          TextButton(
            onPressed: () => context.push(Routes.settings),
            child: Text(l10n.changeBudget),
          ),
        ],
      ),
    );
  }
}
