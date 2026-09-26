import 'package:payoff_engine/payoff_engine.dart';

/// A new loan's figures, for the debt form to start from (the loan
/// calculator's "Add as a debt").
class DebtDraft {
  const DebtDraft({
    required this.balance,
    required this.aprBps,
    required this.payment,
    this.lastPaymentYearMonth,
  });

  final Money balance;
  final int aprBps;
  final Money payment;

  /// `yyyymm`.
  final int? lastPaymentYearMonth;
}
