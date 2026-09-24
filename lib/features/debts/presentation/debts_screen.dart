import 'dart:async';

import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
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
    final settings = ref.watch(settingsControllerProvider).value;
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newDebt),
        icon: const Icon(Icons.add),
        label: Text(l10n.addDebt),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endContained,
      bottomNavigationBar: BottomAppBar(
        child: Row(
          children: [
            FilledButton(
              onPressed: hasDebts
                  ? () => context.push(Routes.strategies)
                  : null,
              child: Text(l10n.compareStrategies),
            ),
          ],
        ),
      ),
      body: switch ((debts, settings)) {
        (AsyncData(:final value), final AppSettings settings) => _DebtsBody(
          debts: value,
          settings: settings,
        ),
        (AsyncError(), _) => _ErrorView(
          onRetry: () => ref.invalidate(debtsProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(context.l10n.errorGeneric),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onRetry, child: Text(context.l10n.retry)),
      ],
    ),
  );
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
      unawaited(
        runGuarded(
          context,
          () => ref.read(debtActionsProvider.notifier).delete(debt.id),
        ),
      );
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

  Future<void> _reorder(List<Debt> debts, int from, int to) async {
    final ids = [for (final d in debts) d.id];
    final moved = ids.removeAt(from);
    ids.insert(to, moved); // onReorderItem already adjusted [to]
    await runGuarded(
      context,
      () => ref.read(debtActionsProvider.notifier).reorder(ids),
    );
  }
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
        DebtType.loan => Icons.account_balance_outlined,
        DebtType.personal => Icons.people_outline,
      }, semanticLabel: debtTypeLabel(l10n, debt.type)),
      title: Text(debt.name),
      subtitle: Text(
        '${l10n.debtApr(formatPercent(debt.aprBps, locale))} · '
        '${l10n.debtMinimum(formatMoney(minimumPayment(debt), locale))}',
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
