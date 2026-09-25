import 'dart:async';

import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/error_view.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/ads/presentation/ad_banner.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
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
            Material(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => context.push(Routes.newDebt),
                        icon: const Icon(Icons.add),
                        label: Text(l10n.addDebt),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: hasDebts
                            ? () => context.push(Routes.strategies)
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

    return Column(
      children: [
        _SummaryCard(
          total: debts.fold(Money.zero(currency), (sum, d) => sum + d.balance),
          minimums: minimums,
          budget: budget,
          locale: locale,
        ),
        if (minimums > budget)
          _ShortfallBanner(shortfall: minimums - budget, locale: locale),
        Expanded(
          child: debts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.debtsEmpty, textAlign: TextAlign.center),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: debts.length,
                  onReorderItem: (from, to) => _reorder(debts, from, to),
                  itemBuilder: (context, i) => _dismissible(debts[i], locale),
                ),
        ),
      ],
    );
  }

  Widget _dismissible(Debt debt, String locale) => Dismissible(
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
    child: DebtTile(debt: debt, locale: locale),
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
  const DebtTile({required this.debt, required this.locale, super.key});

  final Debt debt;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      leading: Icon(switch (debt.type) {
        DebtType.creditCard => Icons.credit_card,
        DebtType.storeCard => Icons.shopping_bag_outlined,
        DebtType.loan => Icons.account_balance_outlined,
        DebtType.overdraft => Icons.account_balance_wallet_outlined,
        DebtType.studentLoan => Icons.school_outlined,
        DebtType.mortgage => Icons.home_outlined,
        DebtType.personal => Icons.people_outline,
        DebtType.other => Icons.receipt_long_outlined,
      }, semanticLabel: debtTypeLabel(l10n, debt.type)),
      title: Text(debt.name),
      subtitle: Text(
        '${l10n.debtApr(formatPercent(debt.aprBps, locale))} · '
        '${l10n.debtMinimum(formatMoney(minimumPayment(debt), locale))}'
        '${debt.transferOffer != null ? ' · ${l10n.debtTransferOffer}' : ''}',
      ),
      trailing: Text(
        formatMoney(debt.balance, locale),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      onTap: () => context.push(Routes.editDebt(debt.id)),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.minimums,
    required this.budget,
    required this.locale,
  });

  final Money total;
  final Money minimums;
  final Money budget;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget figure(String label, Money value) => Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Text(
            formatMoney(value, locale),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            figure(l10n.totalDebt, total),
            figure(l10n.minimumPayments, minimums),
            figure(l10n.monthlyBudget, budget),
          ],
        ),
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
    return Card(
      color: scheme.errorContainer,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: ListTile(
        leading: Icon(Icons.warning_amber, color: scheme.onErrorContainer),
        title: Text(
          l10n.budgetShortfall(formatMoney(shortfall, locale)),
          style: TextStyle(color: scheme.onErrorContainer),
        ),
        trailing: TextButton(
          onPressed: () => context.push(Routes.settings),
          child: Text(l10n.changeBudget),
        ),
      ),
    );
  }
}
