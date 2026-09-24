import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/strategy.dart';

/// Largest accepted amount: 1,000,000,000.00 in a two-decimal currency.
const int kMaxAmountMinor = 100000000000;

/// Most debts one person can enter. Keeps a consolidated total below the
/// calculator's overflow ceiling.
const int kMaxDebts = 50;

/// Longest accepted 0% promotional period.
const int kMaxPromoMonths = 120;

enum DebtValidationError {
  nameEmpty,
  balanceNotPositive,
  balanceTooLarge,
  aprOutOfRange,
  minPaymentPercentOutOfRange,
  minPaymentFloorNegative,
  minPaymentFloorTooLarge,
  floorCurrencyMismatch,
}

enum DebtListValidationError { tooMany, duplicateId, mixedCurrencies }

enum StrategyParametersValidationError {
  consolidationAprOutOfRange,
  transferFeeOutOfRange,
  promoMonthsOutOfRange,
  revertAprOutOfRange,
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
  if (debt.minPaymentFloor.currency != debt.balance.currency)
    DebtValidationError.floorCurrencyMismatch,
};

Set<BudgetValidationError> validateBudget(Money budget) => {
  if (!budget.isPositive) BudgetValidationError.notPositive,
  if (budget.minor > kMaxAmountMinor) BudgetValidationError.tooLarge,
};

/// Checks rules that span the whole list; validate each debt with
/// [validateDebt] as well.
Set<DebtListValidationError> validateDebtList(List<Debt> debts) => {
  if (debts.length > kMaxDebts) DebtListValidationError.tooMany,
  if (debts.map((d) => d.id).toSet().length != debts.length)
    DebtListValidationError.duplicateId,
  if (debts.map((d) => d.balance.currency).toSet().length > 1)
    DebtListValidationError.mixedCurrencies,
};

Set<StrategyParametersValidationError> validateStrategyParameters(
  StrategyParameters p,
) => {
  if (!_isRate(p.consolidationAprBps))
    StrategyParametersValidationError.consolidationAprOutOfRange,
  if (!_isRate(p.transferFeeBps))
    StrategyParametersValidationError.transferFeeOutOfRange,
  if (p.promoMonths < 0 || p.promoMonths > kMaxPromoMonths)
    StrategyParametersValidationError.promoMonthsOutOfRange,
  if (!_isRate(p.revertAprBps))
    StrategyParametersValidationError.revertAprOutOfRange,
};

bool _isRate(int bps) => bps >= 0 && bps <= 10000;
