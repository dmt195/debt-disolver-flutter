import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/debt_kind.dart';
import 'package:payoff_engine/src/debt_ordering.dart';
import 'package:payoff_engine/src/fixed_loan_payment.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/payoff_result.dart';
import 'package:payoff_engine/src/rounding.dart';
import 'package:payoff_engine/src/strategy.dart';

const String kConsolidationDebtId = 'consolidation';
const String kBalanceTransferDebtId = 'balance-transfer';

/// Minimum payment on the balance-transfer card: 3% of the balance.
const int kTransferCardMinimumBps = 300;

sealed class RestructureOutcome {
  const RestructureOutcome();
}

/// The debts a strategy would actually be paying.
final class Restructured extends RestructureOutcome {
  const Restructured({required this.debts, required this.fees, this.change});

  final List<Debt> debts;

  /// One-off fees added to [debts]' balances, e.g. a transfer fee.
  final Money fees;

  /// What the strategy moved or replaced, for display.
  final PlanChange? change;
}

/// The strategy can't be used with these debts.
final class NotRestructurable extends RestructureOutcome {
  const NotRestructurable(this.reason);

  final NotApplicableReason reason;
}

/// Turns the user's [debts] (not empty) into the debts [strategy] pays.
/// Pure: [debts] is not modified.
RestructureOutcome restructure(List<Debt> debts, Strategy strategy) {
  final currency = debts.first.balance.currency;
  final zero = Money.zero(currency);
  return switch (strategy) {
    Avalanche() ||
    Snowball() ||
    CustomOrder() ||
    MinimumsOnly() => Restructured(debts: [...debts], fees: zero),
    Consolidation() => _consolidate(debts, strategy),
    BalanceTransfer() => _transfer(debts, strategy),
  };
}

RestructureOutcome _consolidate(List<Debt> debts, Consolidation c) {
  final currency = debts.first.balance.currency;
  final replaced = [
    for (final d in debts)
      if (isConsolidatable(d.type)) d,
  ];
  if (replaced.isEmpty) {
    return const NotRestructurable(NotApplicableReason.nothingToConsolidate);
  }
  final principal = replaced.fold(0, (sum, d) => sum + d.balance.minor);
  final fee = divideHalfEven(principal * c.feeBps, 10000);
  final payment = fixedLoanPayment(
    balanceMinor: principal + fee,
    aprBps: c.aprBps,
    termMonths: c.termMonths,
  );
  final loan = Debt(
    id: kConsolidationDebtId,
    name: 'Consolidation loan',
    type: DebtType.loan,
    balance: Money(principal + fee, currency),
    aprBps: c.aprBps,
    minPaymentPercentBps: 0,
    minPaymentFloor: Money(payment, currency),
    allowsOverpayment: true,
  );
  return Restructured(
    debts: [
      loan,
      for (final d in debts)
        if (!isConsolidatable(d.type)) d,
    ],
    fees: Money(fee, currency),
    change: PlanChange.consolidation(
      replaced: [
        for (final d in replaced)
          MovedBalance(debtId: d.id, name: d.name, amount: d.balance),
      ],
      fee: Money(fee, currency),
      monthlyPayment: Money(payment, currency),
      termMonths: c.termMonths,
      aprBps: c.aprBps,
    ),
  );
}

RestructureOutcome _transfer(List<Debt> debts, BalanceTransfer t) {
  final currency = debts.first.balance.currency;
  int fee(int amount) => divideHalfEven(amount * t.feeBps, 10000);

  final candidates = [
    for (final d in debts)
      if (isTransferable(d.type) && aprInMonth(d, 1) > 0) d,
  ]..sort((a, b) => compareHighestAprInMonth(a, b, 1));
  // With no limit, assume just enough for every candidate and its own fee.
  final limit =
      t.creditLimit?.minor ??
      candidates.fold<int>(
        0,
        (sum, d) => sum + d.balance.minor + fee(d.balance.minor),
      );

  var room = limit;
  var fees = 0;
  final moved = <String, int>{};
  for (final d in candidates) {
    final amount = _largestFitting(room, d.balance.minor, fee);
    if (amount == 0) continue;
    moved[d.id] = amount;
    fees += fee(amount);
    room -= amount + fee(amount);
  }
  if (moved.isEmpty) {
    return const NotRestructurable(NotApplicableReason.noTransferableBalances);
  }

  final card = Debt(
    id: kBalanceTransferDebtId,
    name: 'Balance transfer card',
    type: DebtType.creditCard,
    balance: Money(moved.values.fold(0, (a, b) => a + b) + fees, currency),
    aprBps: t.revertAprBps,
    minPaymentPercentBps: kTransferCardMinimumBps,
    minPaymentFloor: Money.zero(currency),
    allowsOverpayment: true,
    promo: t.promoMonths > 0 ? Promo(aprBps: 0, months: t.promoMonths) : null,
  );
  return Restructured(
    debts: [
      card,
      for (final d in debts)
        if (d.balance.minor - (moved[d.id] ?? 0) case final left when left > 0)
          d.copyWith(balance: Money(left, currency)),
    ],
    fees: Money(fees, currency),
    change: PlanChange.transfer(
      moved: [
        for (final d in candidates)
          if (moved[d.id] case final amount?)
            MovedBalance(
              debtId: d.id,
              name: d.name,
              amount: Money(amount, currency),
            ),
      ],
      fee: Money(fees, currency),
      creditLimit: Money(limit, currency),
      limitAssumed: t.creditLimit == null,
      promoMonths: t.promoMonths,
    ),
  );
}

/// The largest amount up to [max] that fits in [room] together with its fee.
/// The amount plus its fee rises with the amount, so a binary search finds it.
int _largestFitting(int room, int max, int Function(int) fee) {
  var low = 0;
  var high = max;
  while (low < high) {
    final mid = low + (high - low + 1) ~/ 2;
    if (mid + fee(mid) <= room) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return low;
}
