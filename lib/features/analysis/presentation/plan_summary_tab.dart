import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:payoff_engine/payoff_engine.dart';

class PlanSummaryTab extends ConsumerWidget {
  const PlanSummaryTab({required this.plan, super.key});

  final PayoffPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final now = ref.watch(clockProvider)();
    final theme = Theme.of(context);
    final debtFreeDate = DateTime(now.year, now.month + plan.monthsToClear);
    final firstMonth = plan.months.first;

    Widget row(String label, Money value) => ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(formatMoney(value, locale)),
    );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                title: Text(
                  l10n.debtFreeBy(
                    DateFormat.yMMMM(locale).format(debtFreeDate),
                  ),
                  style: theme.textTheme.titleLarge,
                ),
                subtitle: Text(
                  l10n.debtFreeIn(formatDuration(l10n, plan.monthsToClear)),
                ),
              ),
              row(l10n.totalPaid, plan.totalPaid),
              row(l10n.totalInterest, plan.totalInterest),
              if (plan.totalFees.isPositive) row(l10n.fees, plan.totalFees),
            ],
          ),
        ),
        _Section(l10n.payThisMonth),
        Card(
          child: Column(
            children: [
              for (final (i, debt) in plan.debts.indexed)
                if (firstMonth.payments[i].isPositive)
                  row(planDebtName(l10n, debt), firstMonth.payments[i]),
            ],
          ),
        ),
        _Section(l10n.paymentPriority, hint: l10n.paymentPriorityHint),
        Card(
          child: Column(
            children: [
              for (final (i, debt) in plan.debts.indexed)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(radius: 12, child: Text('${i + 1}')),
                  title: Text(planDebtName(l10n, debt)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (hint != null)
          Text(hint!, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
