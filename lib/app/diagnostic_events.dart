import 'package:debt_destroyer/core/diagnostics.dart';
import 'package:debt_destroyer/features/analysis/data/plan_exporter.dart';
import 'package:debt_destroyer/features/debts/domain/loan_helper.dart';
import 'package:debt_destroyer/features/loans/domain/loan_calculator.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// The only usage events the app sends (diagnostics spec §2.3). Parameters
/// are enum names: never names, amounts, rates, dates or free text.
final class DiagnosticEvent implements UsageEvent {
  const DiagnosticEvent._(this.name, [this.parameters = const {}]);

  DiagnosticEvent.debtAdded(DebtType type)
    : this._('debt_added', {'type': type.name});

  DiagnosticEvent.planFollowed(StrategyId strategy)
    : this._('plan_followed', {'strategy': strategy.name});

  DiagnosticEvent.loanHelperUsed(LoanFigure figure)
    : this._('loan_helper_used', {'figure': figure.name});

  DiagnosticEvent.loanCalculatorUsed(LoanUnknown unknown)
    : this._('loan_calculator_used', {'unknown': unknown.name});

  DiagnosticEvent.scheduleExported(ExportFormat format)
    : this._('schedule_exported', {'format': format.name});

  static const checkInSaved = DiagnosticEvent._('check_in_saved');

  static const debtCleared = DiagnosticEvent._('debt_cleared');

  static const remindersTurnedOn = DiagnosticEvent._('reminders_turned_on');

  /// Every event name there is.
  static const names = {
    'debt_added',
    'plan_followed',
    'check_in_saved',
    'debt_cleared',
    'loan_helper_used',
    'loan_calculator_used',
    'reminders_turned_on',
    'schedule_exported',
  };

  @override
  final String name;

  @override
  final Map<String, String> parameters;
}
