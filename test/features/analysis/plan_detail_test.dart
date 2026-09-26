import 'dart:io';

import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/charts/segment_bar.dart';
import 'package:debt_destroyer/core/charts/stacked_balance_chart.dart';
import 'package:debt_destroyer/features/analysis/data/plan_exporter.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:debt_destroyer/features/progress/domain/progress.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/fake_diagnostics.dart';
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
  // Store card: 1,000.00 at 29.9%. Amex: 500.00 at 12.7% with an offer of
  // 0% for 12 months, 3% fee and 2,000.00 of room: all of the store
  // balance moves (1,000.00 + 30.00 fee).
  final store = testDebt(
    id: 's',
    name: 'Store',
    type: DebtType.storeCard,
    aprBps: 2990,
  );
  final amex = testDebt(
    id: 'a',
    name: 'Amex',
    balance: 50000,
    aprBps: 1270,
    transferOffer: const TransferOffer(
      feeBps: 300,
      promo: Promo(aprBps: 0, months: 12),
      availableCredit: Money(200000, 'GBP'),
    ),
  );

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
    FakeDiagnostics? diagnostics,
  }) => pumpApp(
    tester,
    diagnostics: diagnostics,
    debts: [visa],
    settings: {SettingsKeys.monthlyBudgetMinor: 25000},
    location: Routes.plan(StrategyId.avalanche),
    overrides: [
      if (exporter != null) planExporterProvider.overrideWithValue(exporter),
    ],
  );

  testWidgets('summarises when and how the debts are cleared', (tester) async {
    useTallScreen(tester);
    await open(tester);
    // The fixed test clock is 24 Sep 2026; four payments later is January.
    expect(find.text('Debt-free by'), findsOneWidget);
    expect(find.text('January 2027'), findsOneWidget);
    expect(find.text('4'), findsOneWidget); // months
    expect(find.text('£0.00'), findsOneWidget); // total interest
    expect(find.text('Where your £1,000.00 goes'), findsOneWidget);
    expect(find.text('Milestones'), findsOneWidget);
    expect(find.text('Visa cleared'), findsOneWidget);
    expect(find.text('Debt free'), findsOneWidget);
    expect(find.text('The avalanche method'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets('charts the balance over time', (tester) async {
    await open(tester);
    expect(find.byType(StackedBalanceChart), findsOneWidget);
    expect(find.text('What you owe, month by month'), findsOneWidget);
  });

  testWidgets('shows the month-by-month schedule', (tester) async {
    useTallScreen(tester);
    await open(tester);
    expect(find.text('Full schedule'), findsOneWidget);
    expect(find.text('Visa payment'), findsOneWidget);
    await tester.tap(find.text('Show all 4 months'));
    await tester.pumpAndSettle();
    expect(find.text('Total balance'), findsOneWidget);
    expect(find.text('£750.00'), findsNWidgets(2)); // month 1 balance + total
    expect(find.text('Show all 4 months'), findsNothing);
  });

  testWidgets('says where the money goes, with interest hatched', (
    tester,
  ) async {
    useTallScreen(tester);
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a', name: 'Visa')], // 1,000.00 at 19.9%
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plan(StrategyId.avalanche),
    );
    final bar = tester.widget<SegmentBar>(find.byType(SegmentBar));
    expect(bar.segments.where((s) => s.hazard), hasLength(1));
    expect(find.textContaining('Interest £'), findsOneWidget);
  });

  testWidgets('a legend chip hides a debt from the chart', (tester) async {
    useTallScreen(tester);
    await pumpApp(
      tester,
      debts: [store, amex],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plan(StrategyId.avalanche),
    );
    await tester.tap(find.widgetWithText(FilterChip, 'Store'));
    await tester.pumpAndSettle();
    final chart = tester.widget<StackedBalanceChart>(
      find.byType(StackedBalanceChart),
    );
    expect(chart.hidden, isNotEmpty);
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
    expect(find.byType(StackedBalanceChart), findsNothing);
  });

  testWidgets('explains what a balance transfer changes', (tester) async {
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a', name: 'Visa')], // 1,000.00 at 19.9%
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plan(StrategyId.balanceTransfer),
    );
    final summaryList = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('What changes'),
      100,
      scrollable: summaryList,
    );
    for (final line in [
      'Visa: £1,000.00 moved to the transfer card',
      'Transfer fee: £40.00',
      'Credit limit: £1,040.00 (assumed)',
      '0% for 12 months',
    ]) {
      await tester.scrollUntilVisible(
        find.text(line),
        100,
        scrollable: summaryList,
      );
      expect(find.text(line), findsOneWidget);
    }
  });

  testWidgets('exports name the scenario and what changes', (tester) async {
    final exporter = _RecordingExporter();
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a', name: 'Visa')],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plan(StrategyId.balanceTransfer),
      overrides: [planExporterProvider.overrideWithValue(exporter)],
    );
    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spreadsheet (CSV)'));
    await tester.pumpAndSettle();
    final (table, _, _) = exporter.calls.single;
    expect(table.notes.first, 'Scenario: Current');
    expect(table.notes, contains('Transfer fee: £40.00'));
  });

  testWidgets('names a saved scenario under the title', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [visa],
      scenarios: [
        Scenario(
          id: 's1',
          name: 'Bonus',
          monthlyBudget: const Money(50000, 'GBP'),
          parameters: const StrategyParameters(),
          createdAt: DateTime(2026, 9),
        ),
      ],
      location: Routes.plan(StrategyId.avalanche),
    );
    app.container.read(selectedScenarioIdProvider.notifier).select('s1');
    await tester.pumpAndSettle();
    expect(find.text('Scenario: Bonus'), findsOneWidget);
  });

  testWidgets('shows and exports the pay-more extra', (tester) async {
    final exporter = _RecordingExporter();
    final app = await pumpApp(
      tester,
      debts: [visa],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000}, // £250
      location: Routes.plan(StrategyId.avalanche),
      overrides: [planExporterProvider.overrideWithValue(exporter)],
    );
    app.container.read(extraPaymentProvider.notifier).set(12500); // £125
    await tester.pumpAndSettle();
    expect(
      find.text('Including £125.00 a month extra (£375.00 a month in total)'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spreadsheet (CSV)'));
    await tester.pumpAndSettle();
    final (table, _, _) = exporter.calls.single;
    expect(table.notes, [
      'Scenario: Current',
      'Including £125.00 a month extra (£375.00 a month in total)',
    ]);
  });

  testWidgets('with no extra, no extra line is shown or exported', (
    tester,
  ) async {
    final exporter = _RecordingExporter();
    await pumpApp(
      tester,
      debts: [visa],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.plan(StrategyId.avalanche),
      overrides: [planExporterProvider.overrideWithValue(exporter)],
    );
    expect(find.textContaining('a month extra'), findsNothing);

    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spreadsheet (CSV)'));
    await tester.pumpAndSettle();
    final (table, _, _) = exporter.calls.single;
    expect(table.notes, ['Scenario: Current']);
  });

  testWidgets('lists card moves and names the moved portion', (tester) async {
    await pumpApp(
      tester,
      debts: [store, amex],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plan(StrategyId.cardTransfers),
    );
    const move =
        'Move £1,000.00 from Store to Amex (fee £30.00, 0% for 12 months)';
    await tester.scrollUntilVisible(
      find.text(move),
      100,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text(move), findsOneWidget);
    // The schedule's header names the moved portion (payment and balance).
    // Its columns are off to the side, so scroll to the table itself.
    await tester.scrollUntilVisible(
      find.text('Full schedule'),
      100,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.textContaining('Amex (moved from Store)'), findsWidgets);
  });

  group('follow this plan', () {
    Future<AppHarness> openPlan(WidgetTester tester, StrategyId id) async {
      useTallScreen(tester);
      return await pumpApp(
        tester,
        debts: [testDebt(id: 'a', name: 'Visa')],
        settings: {SettingsKeys.monthlyBudgetMinor: 30000},
        location: Routes.plan(id),
      );
    }

    testWidgets('following another plan asks, then records the switch', (
      tester,
    ) async {
      final app = await openPlan(tester, StrategyId.snowball);
      await tester.tap(find.text('Follow this plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow Smallest balance first'));
      await tester.pumpAndSettle();
      expect(find.text('Follow this plan'), findsNothing);
      final history = await app.progress.load('GBP');
      expect(history.starts.last.reason, StartReason.planSwitched);
    });

    testWidgets('not offered for the plan already followed', (tester) async {
      await openPlan(tester, StrategyId.avalanche);
      expect(find.text('Follow this plan'), findsNothing);
    });

    testWidgets('not offered for a borrowing alternative', (tester) async {
      // Progress can't track the new loan or card, so these aren't followed.
      await openPlan(tester, StrategyId.consolidation);
      expect(find.text('Follow this plan'), findsNothing);
    });

    testWidgets('not offered for minimums only', (tester) async {
      await openPlan(tester, StrategyId.minimumsOnly);
      expect(find.text('Follow this plan'), findsNothing);
    });

    testWidgets('not offered while a saved scenario is chosen', (tester) async {
      final app = await pumpApp(
        tester,
        debts: [testDebt(id: 'a', name: 'Visa')],
        scenarios: [
          Scenario(
            id: 's1',
            name: 'Bonus',
            monthlyBudget: const Money(50000, 'GBP'),
            parameters: const StrategyParameters(),
            createdAt: DateTime(2026, 9),
          ),
        ],
        location: Routes.plan(StrategyId.snowball),
      );
      app.container.read(selectedScenarioIdProvider.notifier).select('s1');
      await tester.pumpAndSettle();
      expect(find.text('Follow this plan'), findsNothing);
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets('legend names are readable in ${brightness.name} mode', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      useTallScreen(tester);
      await pumpApp(
        tester,
        debts: [
          visa,
          testDebt(id: 'car', name: 'Car loan', aprBps: 790),
        ],
        location: Routes.plan(StrategyId.avalanche),
      );
      final c = brightness == Brightness.dark
          ? DestroyerColors.dark
          : DestroyerColors.light;
      Color? labelColour(String name) => tester
          .renderObject<RenderParagraph>(
            find.descendant(
              of: find.byType(FilterChip),
              matching: find.text(name),
            ),
          )
          .text
          .style
          ?.color;
      // Shown debts read in the ink; a hidden one in the secondary ink.
      expect(labelColour('Car loan'), c.ink);
      await tester.tap(
        find.descendant(
          of: find.byType(FilterChip),
          matching: find.text('Car loan'),
        ),
      );
      await tester.pumpAndSettle();
      expect(labelColour('Car loan'), c.ink2);
    });
  }

  testWidgets('counts an export, by format only', (tester) async {
    final fake = FakeDiagnostics();
    await open(tester, exporter: _RecordingExporter(), diagnostics: fake);
    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excel workbook (XLSX)'));
    await tester.pumpAndSettle();
    expect(
      [
        for (final e in fake.events) [e.name, e.parameters],
      ],
      [
        [
          'schedule_exported',
          {'format': 'xlsx'},
        ],
      ],
    );
  });
}
