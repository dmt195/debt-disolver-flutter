import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// What a strategy moved or replaced, as lines of text for the Summary tab
/// and for exports.
List<String> planChangeLines(
  AppLocalizations l10n,
  PlanChange change,
  String locale,
) {
  String money(Money m) => formatMoney(m, locale);
  return switch (change) {
    TransferChange(
      :final moved,
      :final fee,
      :final creditLimit,
      :final limitAssumed,
      :final promoMonths,
    ) =>
      [
        for (final m in moved) l10n.changeMovedToCard(m.name, money(m.amount)),
        l10n.changeTransferFee(money(fee)),
        if (limitAssumed)
          l10n.changeCreditLimitAssumed(money(creditLimit))
        else
          l10n.changeCreditLimit(money(creditLimit)),
        l10n.changePromoMonths(promoMonths),
      ],
    ConsolidationChange(
      :final replaced,
      :final fee,
      :final monthlyPayment,
      :final termMonths,
      :final aprBps,
    ) =>
      [
        for (final r in replaced)
          l10n.changeReplacedByLoan(r.name, money(r.amount)),
        l10n.changeLoanPayment(
          money(monthlyPayment),
          termMonths,
          formatPercent(aprBps, locale),
        ),
        if (fee.isPositive) l10n.changeArrangementFee(money(fee)),
      ],
  };
}
