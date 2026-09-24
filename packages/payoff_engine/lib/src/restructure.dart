import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/debt_ordering.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/rounding.dart';
import 'package:payoff_engine/src/strategy.dart';

const String kConsolidationDebtId = 'consolidation';
const String kBalanceTransferDebtId = 'balance-transfer';

/// The debts a strategy would actually be paying.
final class Restructured {
  const Restructured({required this.debts, required this.fees});

  /// In the order extra money is allocated.
  final List<Debt> debts;

  /// One-off fees added to [debts]' balances, e.g. a transfer fee.
  final Money fees;
}

/// Turns the user's [debts] (not empty) into the debts [strategy] pays.
/// Pure: [debts] is not modified.
Restructured restructure(
  List<Debt> debts,
  Strategy strategy, {
  required Money budget,
}) {
  final currency = debts.first.balance.currency;
  final zero = Money.zero(currency);
  final total = debts.fold(zero, (sum, d) => sum + d.balance);
  return switch (strategy) {
    Avalanche() || Boosted() => Restructured(
      debts: [...debts]..sort(compareHighestAprFirst),
      fees: zero,
    ),
    LowestAprFirst() => Restructured(
      debts: [...debts]..sort(compareLowestAprFirst),
      fees: zero,
    ),
    Consolidation(:final aprBps) => Restructured(
      debts: [
        Debt(
          id: kConsolidationDebtId,
          name: 'Consolidation loan',
          type: DebtType.loan,
          balance: total,
          aprBps: aprBps,
          minPaymentPercentBps: 0,
          minPaymentFloor: budget,
          allowsOverpayment: false,
        ),
      ],
      fees: zero,
    ),
    BalanceTransfer(:final feeBps, :final promoMonths, :final revertAprBps) =>
      () {
        final fee = Money(
          divideHalfEven(total.minor * feeBps, 10000),
          currency,
        );
        return Restructured(
          debts: [
            Debt(
              id: kBalanceTransferDebtId,
              name: 'Balance transfer card',
              type: DebtType.creditCard,
              balance: total + fee,
              aprBps: revertAprBps,
              minPaymentPercentBps: 0,
              minPaymentFloor: budget,
              allowsOverpayment: false,
              promo: promoMonths > 0
                  ? Promo(aprBps: 0, months: promoMonths)
                  : null,
            ),
          ],
          fees: fee,
        );
      }(),
  };
}
