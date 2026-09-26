import 'package:debt_destroyer/app/diagnostic_events.dart';
import 'package:debt_destroyer/app/diagnostics_sync.dart';
import 'package:debt_destroyer/features/analysis/data/plan_exporter.dart';
import 'package:debt_destroyer/features/debts/domain/loan_helper.dart';
import 'package:debt_destroyer/features/loans/domain/loan_calculator.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../helpers/fake_diagnostics.dart';
import '../helpers/test_container.dart';

void main() {
  group('the setting reaches the service', () {
    test('off at start, then on and off as chosen', () async {
      final fake = FakeDiagnostics();
      final container = createTestContainer(diagnostics: fake);
      await container.read(settingsControllerProvider.future);
      container.listen(diagnosticsSettingSyncProvider, (_, _) {});
      await pumpEventQueue();
      expect(fake.enabled, [false]);
      final controller = container.read(settingsControllerProvider.notifier);
      await controller.setShareDiagnostics(on: true);
      await pumpEventQueue();
      await controller.setShareDiagnostics(on: false);
      await pumpEventQueue();
      expect(fake.enabled, [false, true, false]);
      // Opting in discards reports stored while it was off.
      expect(fake.discarded, [false, true, false]);
    });

    test('already opted in: on at start, keeping what is pending', () async {
      final fake = FakeDiagnostics();
      final container = createTestContainer(
        diagnostics: fake,
        prefs: storedSettings({'shareDiagnostics': true}),
      );
      await container.read(settingsControllerProvider.future);
      container.listen(diagnosticsSettingSyncProvider, (_, _) {});
      await pumpEventQueue();
      expect(fake.enabled.last, isTrue);
      expect(fake.discarded, everyElement(isFalse));
    });
  });

  group('the events', () {
    final all = <DiagnosticEvent>[
      for (final t in DebtType.values) DiagnosticEvent.debtAdded(t),
      for (final s in StrategyId.values) DiagnosticEvent.planFollowed(s),
      DiagnosticEvent.checkInSaved,
      DiagnosticEvent.debtCleared,
      for (final f in LoanFigure.values) DiagnosticEvent.loanHelperUsed(f),
      for (final u in LoanUnknown.values) DiagnosticEvent.loanCalculatorUsed(u),
      DiagnosticEvent.remindersTurnedOn,
      for (final f in ExportFormat.values) DiagnosticEvent.scheduleExported(f),
    ];

    test('exactly the eight of the spec', () {
      expect(DiagnosticEvent.names, {
        'debt_added',
        'plan_followed',
        'check_in_saved',
        'debt_cleared',
        'loan_helper_used',
        'loan_calculator_used',
        'reminders_turned_on',
        'schedule_exported',
      });
      expect({for (final e in all) e.name}, DiagnosticEvent.names);
    });

    test('parameters are only ever enum names', () {
      final allowed = {
        for (final values in <List<Enum>>[
          DebtType.values,
          StrategyId.values,
          LoanFigure.values,
          LoanUnknown.values,
          ExportFormat.values,
        ])
          for (final v in values) v.name,
      };
      for (final e in all) {
        for (final value in e.parameters.values) {
          expect(allowed, contains(value), reason: e.name);
        }
      }
    });
  });
}
