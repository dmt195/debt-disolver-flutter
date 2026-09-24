import 'package:payoff_engine/src/debt.dart';

/// Whether a balance of this kind can move to a balance-transfer card.
bool isTransferable(DebtType type) => switch (type) {
  DebtType.creditCard || DebtType.storeCard => true,
  DebtType.loan ||
  DebtType.overdraft ||
  DebtType.studentLoan ||
  DebtType.mortgage ||
  DebtType.personal ||
  DebtType.other => false,
};

/// Whether a consolidation loan can replace a debt of this kind.
bool isConsolidatable(DebtType type) => switch (type) {
  DebtType.creditCard ||
  DebtType.storeCard ||
  DebtType.loan ||
  DebtType.overdraft => true,
  DebtType.studentLoan ||
  DebtType.mortgage ||
  DebtType.personal ||
  DebtType.other => false,
};

/// Whether a new debt of this kind should take extra payments. Student loans
/// are income-contingent and written off; mortgages are usually the cheapest
/// debt. Overpaying either rarely helps.
bool defaultAllowsOverpayment(DebtType type) => switch (type) {
  DebtType.studentLoan || DebtType.mortgage => false,
  DebtType.creditCard ||
  DebtType.storeCard ||
  DebtType.loan ||
  DebtType.overdraft ||
  DebtType.personal ||
  DebtType.other => true,
};
