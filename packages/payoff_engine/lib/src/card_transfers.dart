import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/debt_kind.dart';
import 'package:payoff_engine/src/fee_fit.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/payoff_result.dart';
import 'package:payoff_engine/src/rounding.dart';

/// Most moves the card-transfers strategy makes.
const int kMaxCardMoves = 10;

/// [debts] with [moves] applied: each source reduced by what left it (and
/// dropped if emptied), each target followed by a portion per move onto it.
/// `groups` lists each card's portions as indexes, its own debt first.
({List<Debt> debts, List<List<int>> groups}) applyCardMoves(
  List<Debt> debts,
  List<CardMove> moves,
) {
  final out = <Debt>[];
  final groups = <List<int>>[];
  for (final d in debts) {
    final left =
        d.balance.minor -
        moves
            .where((m) => m.fromDebtId == d.id)
            .fold<int>(0, (s, m) => s + m.amount.minor);
    if (left <= 0) continue;
    final group = [out.length];
    out.add(d.copyWith(balance: Money(left, d.balance.currency)));
    for (final m in moves.where((m) => m.toDebtId == d.id)) {
      group.add(out.length);
      out.add(
        Debt(
          id: '${d.id}#from-${m.fromDebtId}',
          name: '${d.name} (moved from ${m.fromName})',
          type: d.type,
          balance: m.amount + m.fee,
          aprBps: d.aprBps,
          minPaymentPercentBps: 0,
          minPaymentFloor: Money.zero(d.balance.currency),
          allowsOverpayment: d.allowsOverpayment,
          promo: m.promo,
        ),
      );
    }
    groups.add(group);
  }
  return (debts: out, groups: groups);
}

/// The moves worth simulating next, on top of [moves]: from a transferable
/// debt that hasn't received money onto another debt with an offer that
/// hasn't given any, where money moved would pay a lower rate in month 1,
/// each for the most that fits the target's remaining room with its fee.
/// Ordered by source name, then target name (then ids).
List<CardMove> cardMoveCandidates(List<Debt> debts, List<CardMove> moves) {
  final gave = {for (final m in moves) m.fromDebtId};
  final received = {for (final m in moves) m.toDebtId};
  int byName(Debt a, Debt b) {
    final n = a.name.compareTo(b.name);
    return n != 0 ? n : a.id.compareTo(b.id);
  }

  final sorted = [...debts]..sort(byName);
  return [
    for (final from in sorted)
      if (isTransferable(from.type) && !received.contains(from.id))
        for (final to in sorted)
          if (to.transferOffer case final offer?)
            if (to.id != from.id &&
                !gave.contains(to.id) &&
                !moves.any(
                  (m) => m.fromDebtId == from.id && m.toDebtId == to.id,
                ))
              ?_candidate(from, to, offer, moves),
  ];
}

CardMove? _candidate(
  Debt from,
  Debt to,
  TransferOffer offer,
  List<CardMove> moves,
) {
  final movedRate = offer.promo?.aprBps ?? to.aprBps;
  if (aprInMonth(from, 1) <= movedRate) return null;
  int fee(int amount) => divideHalfEven(amount * offer.feeBps, 10000);
  final left =
      from.balance.minor -
      moves
          .where((m) => m.fromDebtId == from.id)
          .fold<int>(0, (s, m) => s + m.amount.minor);
  final room =
      offer.availableCredit.minor -
      moves
          .where((m) => m.toDebtId == to.id)
          .fold<int>(0, (s, m) => s + m.amount.minor + m.fee.minor);
  final amount = largestFittingAmount(room, left, fee);
  if (amount == 0) return null;
  final currency = from.balance.currency;
  return CardMove(
    fromDebtId: from.id,
    fromName: from.name,
    toDebtId: to.id,
    toName: to.name,
    amount: Money(amount, currency),
    fee: Money(fee(amount), currency),
    promo: offer.promo,
  );
}
