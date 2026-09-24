import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:excel/excel.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// [table] as CSV (RFC 4180, CRLF line ends). Amounts are plain numbers in
/// major units with a `.` decimal point, e.g. `1234.56`, so spreadsheets in
/// any locale read them as numbers.
String scheduleToCsv(ScheduleTable table) {
  final lines = [
    table.headers.map(_csvField).join(','),
    for (final row in table.rows)
      [
        '${row.month}',
        for (final amount in row.amounts) majorUnitsText(amount),
      ].join(','),
  ];
  return '${lines.join('\r\n')}\r\n';
}

/// [table] as an XLSX workbook with one sheet, amounts as numbers.
List<int> scheduleToXlsx(ScheduleTable table, {String sheetName = 'Schedule'}) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet()!;
  excel
    ..rename(defaultSheet, sheetName)
    ..appendRow(sheetName, [for (final h in table.headers) TextCellValue(h)]);
  for (final row in table.rows) {
    excel.appendRow(sheetName, [
      IntCellValue(row.month),
      for (final amount in row.amounts)
        DoubleCellValue(double.parse(majorUnitsText(amount))),
    ]);
  }
  return excel.save()!;
}

/// [money] in major units as exact decimal text, e.g. `1234.56`.
String majorUnitsText(Money money) {
  final digits = currencyDecimalDigits(money.currency);
  final text = money.minor.abs().toString().padLeft(digits + 1, '0');
  final sign = money.isNegative ? '-' : '';
  if (digits == 0) return '$sign$text';
  final split = text.length - digits;
  return '$sign${text.substring(0, split)}.${text.substring(split)}';
}

String _csvField(String value) {
  if (!value.contains(RegExp('[",\r\n]'))) return value;
  return '"${value.replaceAll('"', '""')}"';
}
