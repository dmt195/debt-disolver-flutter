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
  StrategyId.minimumsOnly => l10n.strategyMinimumsOnlyDescription,
  StrategyId.consolidation => l10n.strategyConsolidationDescription(
    formatPercent(p.consolidationAprBps, locale),
  ),
  StrategyId.balanceTransfer => l10n.strategyBalanceTransferDescription(
    p.promoMonths,
    formatPercent(p.transferFeeBps, locale),
    formatPercent(p.revertAprBps, locale),
  ),
};

/// The name to show for a debt in a plan; the calculator's synthetic debts
/// get translated names.
String planDebtName(AppLocalizations l10n, PlanDebt debt) => switch (debt.id) {
  kConsolidationDebtId => l10n.consolidationLoanName,
  kBalanceTransferDebtId => l10n.balanceTransferCardName,
  _ => debt.name,
};

/// e.g. `2 years 3 months`, `1 year`, `5 months`.
String formatDuration(AppLocalizations l10n, int months) {
  final years = months ~/ 12;
  final rest = months % 12;
  if (years == 0) return l10n.months(rest);
  if (rest == 0) return l10n.years(years);
  return l10n.yearsAndMonths(l10n.years(years), l10n.months(rest));
}
