import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:debt_destroyer/features/analysis/data/plan_exporter.dart';
import 'package:debt_destroyer/features/analysis/data/schedule_export.dart';
import 'package:debt_destroyer/features/analysis/domain/plan_series.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

Money gbp(int minor) => Money(minor, 'GBP');

/// Two debts, two months: payments and balances chosen to be easy to check.
final plan = PayoffPlan(
  debts: [
    PlanDebt(id: 'a', name: 'Visa', startingBalance: gbp(15000)),
    PlanDebt(id: 'b', name: 'Loan, "car"', startingBalance: gbp(5050)),
  ],
  months: [
    MonthRow(
      month: 1,
      interest: [gbp(0), gbp(0)],
      payments: [gbp(10000), gbp(2525)],
      closingBalances: [gbp(5000), gbp(2525)],
    ),
    MonthRow(
      month: 2,
      interest: [gbp(0), gbp(0)],
      payments: [gbp(5000), gbp(2525)],
      closingBalances: [gbp(0), gbp(0)],
    ),
  ],
  totalPaid: gbp(20050),
  totalInterest: gbp(0),
  totalFees: gbp(0),
);

const labels = ScheduleLabels(
  month: 'Month',
  payment: _payment,
  balance: _balance,
  totalPayment: 'Total payment',
  totalBalance: 'Total balance',
);
String _payment(String name) => '$name payment';
String _balance(String name) => '$name balance';

ScheduleTable table() => buildScheduleTable(
  plan,
  debtNames: ['Visa', 'Loan, "car"'],
  labels: labels,
);

void main() {
  test('lays out payments and balances per debt, then totals', () {
    final t = table();
    expect(t.headers, [
      'Month',
      'Visa payment',
      'Visa balance',
      'Loan, "car" payment',
      'Loan, "car" balance',
      'Total payment',
      'Total balance',
    ]);
    expect(t.rows.first.month, 1);
    expect(t.rows.first.amounts, [
      gbp(10000),
      gbp(5000),
      gbp(2525),
      gbp(2525),
      gbp(12525),
      gbp(7525),
    ]);
  });

  test('majorUnitsText writes exact decimals', () {
    expect(majorUnitsText(gbp(123456)), '1234.56');
    expect(majorUnitsText(gbp(5)), '0.05');
    expect(majorUnitsText(gbp(0)), '0.00');
    expect(majorUnitsText(gbp(-150)), '-1.50');
    expect(majorUnitsText(const Money(1235, 'JPY')), '1235');
  });

  test('CSV quotes awkward headers and uses plain numbers', () {
    const header = [
      'Month',
      'Visa payment',
      'Visa balance',
      '"Loan, ""car"" payment"',
      '"Loan, ""car"" balance"',
      'Total payment',
      'Total balance',
    ];
    final lines = [
      header.join(','),
      '1,100.00,50.00,25.25,25.25,125.25,75.25',
      '2,50.00,0.00,25.25,0.00,75.25,0.00',
      '',
    ];
    // The byte order mark makes Excel read the file as UTF-8.
    expect(scheduleToCsv(table()), '﻿${lines.join('\r\n')}');
  });

  test('XLSX holds the same table with numeric cells', () {
    final workbook = Excel.decodeBytes(scheduleToXlsx(table()));
    final rows = workbook.tables['Schedule']!.rows;
    expect(rows, hasLength(3));
    expect(rows[0][1]!.value, TextCellValue('Visa payment'));
    // Whole numbers read back as integer cells; either way they're numbers.
    num numeric(CellValue? v) => switch (v) {
      IntCellValue(:final value) => value,
      DoubleCellValue(:final value) => value,
      _ => throw StateError('not a number: $v'),
    };
    expect(numeric(rows[1][0]!.value), 1);
    expect(numeric(rows[1][1]!.value), 100);
    expect(numeric(rows[2][5]!.value), 75.25);
  });

  test('stacked balances start from the starting balances', () {
    expect(stackedBalances(plan), [
      [150.0, 200.5],
      [50.0, 75.25],
      [0.0, 0.0],
    ]);
  });

  test(
    'PlanExporter writes the file and hands it to the share sheet',
    () async {
      final dir = await Directory.systemTemp.createTemp('export');
      addTearDown(() => dir.delete(recursive: true));
      final sharer = _RecordingSharer();
      final exporter = PlanExporter(sharer, () async => dir);

      const origin = Rect.fromLTWH(10, 20, 30, 40);
      final csv = await exporter.export(
        table(),
        ExportFormat.csv,
        baseName: 'plan',
        origin: origin,
      );
      expect(csv.path, '${dir.path}/plan.csv');
      // Compare bytes: reading back as a string would drop the byte order mark.
      expect(await csv.readAsBytes(), utf8.encode(scheduleToCsv(table())));
      expect(sharer.shared.single, (csv.path, 'text/csv'));
      expect(sharer.origins.single, origin);

      final xlsx = await exporter.export(
        table(),
        ExportFormat.xlsx,
        baseName: 'plan',
      );
      expect(xlsx.path.endsWith('.xlsx'), isTrue);
      expect(
        Excel.decodeBytes(await xlsx.readAsBytes()).tables,
        contains('Schedule'),
      );
    },
  );

  test('CSV is valid UTF-8 for non-ASCII names', () {
    final t = buildScheduleTable(
      plan,
      debtNames: ['Crédit', 'Ünicode'],
      labels: labels,
    );
    expect(
      utf8.decode(utf8.encode(scheduleToCsv(t))),
      contains('Crédit payment'),
    );
  });

  ScheduleTable withNotes() => buildScheduleTable(
    plan,
    debtNames: ['Visa', 'Loan, "car"'],
    labels: labels,
    notes: ['Scenario: Current', 'Transfer fee: £1,000.00'],
  );

  test('CSV puts notes above the schedule, then a blank line', () {
    final lines = scheduleToCsv(withNotes()).substring(1).split('\r\n');
    const headerLine =
        'Month,Visa payment,Visa balance,"Loan, ""car"" payment","Loan, '
        '""car"" balance",Total payment,Total balance';
    expect(lines.take(4), [
      'Scenario: Current',
      '"Transfer fee: £1,000.00"',
      '',
      headerLine,
    ]);
  });

  test('XLSX puts notes above the schedule, then a blank row', () {
    final rows = Excel.decodeBytes(scheduleToXlsx(withNotes()))
        .tables['Schedule']!
        .rows;
    expect(rows[0][0]!.value, TextCellValue('Scenario: Current'));
    expect(rows[3][0]!.value, TextCellValue('Month'));
  });
}

class _RecordingSharer implements FileSharer {
  final shared = <(String, String)>[];
  final origins = <Rect?>[];

  @override
  Future<void> shareFile(
    File file, {
    required String mimeType,
    String? subject,
    Rect? origin,
  }) async {
    shared.add((file.path, mimeType));
    origins.add(origin);
  }
}
