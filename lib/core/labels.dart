import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:payoff_engine/payoff_engine.dart';

String debtTypeLabel(AppLocalizations l10n, DebtType type) => switch (type) {
  DebtType.creditCard => l10n.debtTypeCreditCard,
  DebtType.storeCard => l10n.debtTypeStoreCard,
  DebtType.loan => l10n.debtTypeLoan,
  DebtType.overdraft => l10n.debtTypeOverdraft,
  DebtType.studentLoan => l10n.debtTypeStudentLoan,
  DebtType.mortgage => l10n.debtTypeMortgage,
  DebtType.personal => l10n.debtTypePersonal,
  DebtType.other => l10n.debtTypeOther,
};

String strategyName(AppLocalizations l10n, StrategyId id) => switch (id) {
  StrategyId.avalanche => l10n.strategyAvalanche,
  StrategyId.snowball => l10n.strategySnowball,
  StrategyId.customOrder => l10n.strategyCustomOrder,
  StrategyId.cardTransfers => l10n.strategyCardTransfers,
  StrategyId.consolidation => l10n.strategyConsolidation,
  StrategyId.balanceTransfer => l10n.strategyBalanceTransfer,
  StrategyId.minimumsOnly => l10n.strategyMinimumsOnly,
};

String strategyDescription(
  AppLocalizations l10n,
  StrategyId id,
  StrategyParameters p,
  String locale,
) => switch (id) {
  StrategyId.avalanche => l10n.strategyAvalancheDescription,
  StrategyId.snowball => l10n.strategySnowballDescription,
  StrategyId.customOrder => l10n.strategyCustomOrderDescription,
  StrategyId.cardTransfers => l10n.strategyCardTransfersDescription,
  StrategyId.minimumsOnly => l10n.strategyMinimumsOnlyDescription,
  StrategyId.consolidation => l10n.strategyConsolidationDescription(
    p.consolidationTermMonths,
    formatPercent(p.consolidationAprBps, locale),
  ),
  StrategyId.balanceTransfer =>
    p.promoMonths == 0
        ? l10n.strategyBalanceTransferNoPromoDescription(
            formatPercent(p.transferFeeBps, locale),
            formatPercent(p.revertAprBps, locale),
          )
        : l10n.strategyBalanceTransferDescription(
            p.promoMonths,
            formatPercent(p.transferFeeBps, locale),
            formatPercent(p.revertAprBps, locale),
          ),
};

/// The popular nickname for a strategy, if it has one.
String? strategyNickname(AppLocalizations l10n, StrategyId id) => switch (id) {
  StrategyId.avalanche => l10n.strategyAvalancheNickname,
  StrategyId.snowball => l10n.strategySnowballNickname,
  StrategyId.customOrder ||
  StrategyId.cardTransfers ||
  StrategyId.consolidation ||
  StrategyId.balanceTransfer ||
  StrategyId.minimumsOnly => null,
};

/// Who a strategy suits; null for the minimums-only baseline.
String? strategyBestFor(AppLocalizations l10n, StrategyId id) => switch (id) {
  StrategyId.avalanche => l10n.strategyAvalancheBestFor,
  StrategyId.snowball => l10n.strategySnowballBestFor,
  StrategyId.customOrder => l10n.strategyCustomOrderBestFor,
  StrategyId.cardTransfers => l10n.strategyCardTransfersBestFor,
  StrategyId.consolidation => l10n.strategyConsolidationBestFor,
  StrategyId.balanceTransfer => l10n.strategyBalanceTransferBestFor,
  StrategyId.minimumsOnly => null,
};

/// The name to show for a debt in a plan; the calculator's synthetic debts
/// get translated names.
String planDebtName(AppLocalizations l10n, PlanDebt debt) => switch (debt.id) {
  kConsolidationDebtId => l10n.consolidationLoanName,
  kBalanceTransferDebtId => l10n.balanceTransferCardName,
  _ => debt.name,
};

/// Why a strategy can't be used with the current debts.
String notApplicableReason(
  AppLocalizations l10n,
  NotApplicableReason reason,
) => switch (reason) {
  NotApplicableReason.noTransferableBalances => l10n.notApplicableNoTransfer,
  NotApplicableReason.nothingToConsolidate => l10n.notApplicableNoConsolidation,
  NotApplicableReason.noCardOffers => l10n.notApplicableNoCardOffers,
  NotApplicableReason.noWorthwhileMoves => l10n.notApplicableNoWorthwhileMoves,
};

/// e.g. `2 years 3 months`, `1 year`, `5 months`.
String formatDuration(AppLocalizations l10n, int months) {
  final years = months ~/ 12;
  final rest = months % 12;
  if (years == 0) return l10n.months(rest);
  if (rest == 0) return l10n.years(years);
  return l10n.yearsAndMonths(l10n.years(years), l10n.months(rest));
}

/// English ordinal: 1st, 2nd, 3rd, 4th … 11th, 12th, 13th, 21st.
String ordinal(int n) {
  final lastTwo = n % 100;
  final suffix = lastTwo >= 11 && lastTwo <= 13
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix';
}
