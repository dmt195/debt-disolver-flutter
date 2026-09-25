import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/debt_kind.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/strategy.dart';

/// Largest accepted amount: 1,000,000,000.00 in a two-decimal currency.
const int kMaxAmountMinor = 100000000000;

/// Most debts one person can enter. Keeps a consolidated total below the
/// calculator's overflow ceiling.
const int kMaxDebts = 50;

/// Longest accepted 0% promotional period.
const int kMaxPromoMonths = 120;

/// Accepted consolidation loan terms, in months.
const int kMinConsolidationTermMonths = 6;
const int kMaxConsolidationTermMonths = 120;

/// Highest accepted arrangement fee: 20%.
const int kMaxConsolidationFeeBps = 2000;

enum DebtValidationError {
  nameEmpty,
  balanceNotPositive,
  balanceTooLarge,
  aprOutOfRange,
  minPaymentPercentOutOfRange,
  minPaymentFloorNegative,
  minPaymentFloorTooLarge,
  floorCurrencyMismatch,
  promoAprOutOfRange,
  promoMonthsOutOfRange,
  offerOnNonCard,
  offerFeeOutOfRange,
  offerPromoAprOutOfRange,
  offerPromoMonthsOutOfRange,
  offerCreditNotPositive,
  offerCreditTooLarge,
  offerCurrencyMismatch,
}

enum DebtListValidationError { tooMany, duplicateId, mixedCurrencies }

enum StrategyParametersValidationError {
  consolidationAprOutOfRange,
  consolidationTermOutOfRange,
  consolidationFeeOutOfRange,
  transferFeeOutOfRange,
  promoMonthsOutOfRange,
  revertAprOutOfRange,
  creditLimitNotPositive,
  creditLimitTooLarge,
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
  if (debt.promo case final promo? when !_isRate(promo.aprBps))
    DebtValidationError.promoAprOutOfRange,
  if (debt.promo case final promo?
      when promo.months < 1 || promo.months > kMaxPromoMonths)
    DebtValidationError.promoMonthsOutOfRange,
  if (debt.transferOffer != null && !isTransferable(debt.type))
    DebtValidationError.offerOnNonCard,
  if (debt.transferOffer case final o? when !_isRate(o.feeBps))
    DebtValidationError.offerFeeOutOfRange,
  if (debt.transferOffer?.promo case final p? when !_isRate(p.aprBps))
    DebtValidationError.offerPromoAprOutOfRange,
  if (debt.transferOffer?.promo case final p?
      when p.months < 1 || p.months > kMaxPromoMonths)
    DebtValidationError.offerPromoMonthsOutOfRange,
  if (debt.transferOffer case final o? when !o.availableCredit.isPositive)
    DebtValidationError.offerCreditNotPositive,
  if (debt.transferOffer case final o?
      when o.availableCredit.minor > kMaxAmountMinor)
    DebtValidationError.offerCreditTooLarge,
  if (debt.transferOffer case final o?
      when o.availableCredit.currency != debt.balance.currency)
    DebtValidationError.offerCurrencyMismatch,
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
  if (p.consolidationTermMonths < kMinConsolidationTermMonths ||
      p.consolidationTermMonths > kMaxConsolidationTermMonths)
    StrategyParametersValidationError.consolidationTermOutOfRange,
  if (p.consolidationFeeBps < 0 ||
      p.consolidationFeeBps > kMaxConsolidationFeeBps)
    StrategyParametersValidationError.consolidationFeeOutOfRange,
  if (!_isRate(p.transferFeeBps))
    StrategyParametersValidationError.transferFeeOutOfRange,
  if (p.promoMonths < 0 || p.promoMonths > kMaxPromoMonths)
    StrategyParametersValidationError.promoMonthsOutOfRange,
  if (!_isRate(p.revertAprBps))
    StrategyParametersValidationError.revertAprOutOfRange,
  if (p.transferCreditLimit case final limit? when !limit.isPositive)
    StrategyParametersValidationError.creditLimitNotPositive,
  if (p.transferCreditLimit case final limit?
      when limit.minor > kMaxAmountMinor)
    StrategyParametersValidationError.creditLimitTooLarge,
};

bool _isRate(int bps) => bps >= 0 && bps <= 10000;
