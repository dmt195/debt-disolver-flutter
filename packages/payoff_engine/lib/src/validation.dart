import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/money.dart';

/// Largest accepted amount: 1,000,000,000.00 in a two-decimal currency.
const int kMaxAmountMinor = 100000000000;

enum DebtValidationError {
  nameEmpty,
  balanceNotPositive,
  balanceTooLarge,
  aprOutOfRange,
  minPaymentPercentOutOfRange,
  minPaymentFloorNegative,
  minPaymentFloorTooLarge,
}

enum BudgetValidationError { notPositive, tooLarge }

Set<DebtValidationError> validateDebt(Debt debt) => {
  if (debt.name.trim().isEmpty) DebtValidationError.nameEmpty,
  if (!debt.balance.isPositive) DebtValidationError.balanceNotPositive,
  if (debt.balance.minor > kMaxAmountMinor) DebtValidationError.balanceTooLarge,
  if (debt.aprBps < 0 || debt.aprBps > 10000) DebtValidationError.aprOutOfRange,
  if (debt.minPaymentPercentBps < 0 || debt.minPaymentPercentBps > 10000)
    DebtValidationError.minPaymentPercentOutOfRange,
  if (debt.minPaymentFloor.isNegative)
    DebtValidationError.minPaymentFloorNegative,
  if (debt.minPaymentFloor.minor > kMaxAmountMinor)
    DebtValidationError.minPaymentFloorTooLarge,
};

Set<BudgetValidationError> validateBudget(Money budget) => {
  if (!budget.isPositive) BudgetValidationError.notPositive,
  if (budget.minor > kMaxAmountMinor) BudgetValidationError.tooLarge,
};
