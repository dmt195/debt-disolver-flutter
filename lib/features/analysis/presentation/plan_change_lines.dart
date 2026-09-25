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
        if (promoMonths > 0) l10n.changePromoMonths(promoMonths),
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
    CardTransferChange(:final moves) => [
      for (final m in moves)
        if (m.promo case final promo?)
          l10n.changeCardMovePromo(
            money(m.amount),
            m.fromName,
            m.toName,
            money(m.fee),
            formatPercent(promo.aprBps, locale),
            promo.months,
          )
        else
          l10n.changeCardMove(
            money(m.amount),
            m.fromName,
            m.toName,
            money(m.fee),
          ),
      l10n.changeCardMoveReminder,
    ],
  };
}
