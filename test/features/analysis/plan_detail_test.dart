import 'dart:io';

import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/analysis/data/plan_exporter.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

class _RecordingExporter extends PlanExporter {
  _RecordingExporter() : super(_NoSharer(), () async => Directory.systemTemp);

  final calls = <(ScheduleTable, ExportFormat, String)>[];
  final origins = <Rect?>[];
  Exception? failWith;

  @override
  Future<File> export(
    ScheduleTable table,
    ExportFormat format, {
    required String baseName,
    String? subject,
    Rect? origin,
  }) async {
    if (failWith case final error?) throw error;
    calls.add((table, format, baseName));
    origins.add(origin);
    return File('unused');
  }
}

class _NoSharer implements FileSharer {
  @override
  Future<void> shareFile(
    File file, {
    required String mimeType,
    String? subject,
    Rect? origin,
  }) async {}
}

void main() {
  final visa = testDebt(
    id: 'a',
    name: 'Visa',
    aprBps: 0,
    minPaymentPercentBps: 0,
    minPaymentFloor: 0,
  );

  Future<AppHarness> open(
    WidgetTester tester, {
    _RecordingExporter? exporter,
  }) => pumpApp(
    tester,
    debts: [visa],
    settings: {SettingsKeys.monthlyBudgetMinor: 25000},
    location: Routes.plan(StrategyId.avalanche),
    overrides: [
      if (exporter != null) planExporterProvider.overrideWithValue(exporter),
    ],
  );

  testWidgets('summarises when and how the debts are cleared', (tester) async {
    await open(tester);
    // The fixed test clock is 24 Sep 2026; four payments later is January.
    expect(find.text('Debt-free by January 2027'), findsOneWidget);
    expect(find.text('Debt-free in 4 months'), findsOneWidget);
    expect(find.text('£1,000.00'), findsOneWidget); // total paid
    expect(find.text('£0.00'), findsOneWidget); // total interest
    expect(find.text('£250.00'), findsOneWidget); // this month
    expect(find.text('Payoff order'), findsOneWidget);
  });

  testWidgets('charts the balance over time', (tester) async {
    await open(tester);
    await tester.tap(find.text('Chart'));
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Balance over time'), findsOneWidget);
  });

  testWidgets('shows the month-by-month schedule', (tester) async {
    await open(tester);
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Visa payment'), findsOneWidget);
    expect(find.text('Total balance'), findsOneWidget);
    expect(find.text('£750.00'), findsNWidgets(2)); // month 1 balance + total
  });

  testWidgets('shares the schedule as CSV or XLSX', (tester) async {
    final exporter = _RecordingExporter();
    await open(tester, exporter: exporter);
    for (final (label, format) in [
      ('Spreadsheet (CSV)', ExportFormat.csv),
      ('Excel workbook (XLSX)', ExportFormat.xlsx),
    ]) {
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(exporter.calls.last.$2, format);
    }
    final (table, _, baseName) = exporter.calls.first;
    expect(baseName, 'debt-plan-avalanche');
    // iPads need to know where the share sheet points.
    expect(exporter.origins, everyElement(isNotNull));
    expect(table.rows, hasLength(4));
  });

  testWidgets('a failed export tells the user', (tester) async {
    final exporter = _RecordingExporter()..failWith = Exception('no space');
    await open(tester, exporter: exporter);
    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spreadsheet (CSV)'));
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't share this plan. Please try again."),
      findsOneWidget,
    );
  });

  testWidgets('an infeasible plan is explained, not drawn', (tester) async {
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a')],
      settings: {SettingsKeys.monthlyBudgetMinor: 1000},
      location: Routes.plan(StrategyId.avalanche),
    );
    expect(
      find.text("This plan isn't available for your current debts and budget."),
      findsOneWidget,
    );
    expect(find.byType(TabBar), findsNothing);
  });
}
