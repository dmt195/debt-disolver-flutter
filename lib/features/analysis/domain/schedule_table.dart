import 'package:flutter/foundation.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// A plan laid out as rows for the schedule tab and for export: for each
/// month, every debt's payment and closing balance, then the totals.
@immutable
class ScheduleTable {
  const ScheduleTable({required this.headers, required this.rows});

  /// `Month`, then per debt `<name> payment`, `<name> balance`, then
  /// `Total payment`, `Total balance`.
  final List<String> headers;
  final List<ScheduleRow> rows;
}

@immutable
class ScheduleRow {
  const ScheduleRow({required this.month, required this.amounts});

  final int month;

  /// In [ScheduleTable.headers] order after `Month`.
  final List<Money> amounts;
}

/// Column labels, supplied by the caller so they can be translated.
@immutable
class ScheduleLabels {
  const ScheduleLabels({
    required this.month,
    required this.payment,
    required this.balance,
    required this.totalPayment,
    required this.totalBalance,
  });

  final String month;
  final String Function(String debtName) payment;
  final String Function(String debtName) balance;
  final String totalPayment;
  final String totalBalance;
}

ScheduleTable buildScheduleTable(
  PayoffPlan plan, {
  required List<String> debtNames,
  required ScheduleLabels labels,
}) {
  assert(debtNames.length == plan.debts.length, 'one name per plan debt');
  final currency = plan.totalPaid.currency;
  Money sum(List<Money> values) =>
      values.fold(Money.zero(currency), (a, b) => a + b);
  return ScheduleTable(
    headers: [
      labels.month,
      for (final name in debtNames) ...[
        labels.payment(name),
        labels.balance(name),
      ],
      labels.totalPayment,
      labels.totalBalance,
    ],
    rows: [
      for (final row in plan.months)
        ScheduleRow(
          month: row.month,
          amounts: [
            for (var i = 0; i < plan.debts.length; i++) ...[
              row.payments[i],
              row.closingBalances[i],
            ],
            sum(row.payments),
            sum(row.closingBalances),
          ],
        ),
    ],
  );
}
