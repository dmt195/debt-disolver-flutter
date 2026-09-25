import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/src/money.dart';

part 'debt.freezed.dart';

/// Stored by name in the app's database: renaming a value breaks existing
/// rows unless a migration renames them too. Declaration order is the order
/// the debt form lists them in.
enum DebtType {
  creditCard,
  storeCard,
  loan,
  overdraft,
  studentLoan,
  mortgage,
  personal,
  other,
}

/// A lower rate for the first [months] months of a plan.
@freezed
abstract class Promo with _$Promo {
  const factory Promo({
    /// Rate during the promotion, in basis points (usually 0).
    required int aprBps,

    /// Months the promotion still applies, counting a plan's first month as
    /// month 1.
    required int months,
  }) = _Promo;
}

/// A balance-transfer offer on one of the user's own cards: what moving a
/// balance onto it costs, and how much it can take.
@freezed
abstract class TransferOffer with _$TransferOffer {
  const factory TransferOffer({
    /// Fee as a share of the amount moved, in basis points.
    required int feeBps,

    /// Room left on the card; moves plus their fees must fit.
    required Money availableCredit,

    /// Rate and length for moved money, counted from the move (a plan's
    /// month 1). Afterwards moved money pays the card's own APR.
    Promo? promo,
  }) = _TransferOffer;
}

@freezed
abstract class Debt with _$Debt {
  const factory Debt({
    required String id,
    required String name,
    required DebtType type,
    required Money balance,

    /// Annual percentage rate in basis points (1995 = 19.95%).
    required int aprBps,

    /// Minimum payment as a share of the balance, in basis points.
    required int minPaymentPercentBps,

    /// The minimum payment is never less than this (unless the balance is).
    required Money minPaymentFloor,

    /// Whether payments above the minimum are allowed.
    required bool allowsOverpayment,

    /// A promotional rate charged instead of [aprBps] while it lasts.
    Promo? promo,

    /// A balance-transfer offer on this card, if the user has one.
    TransferOffer? transferOffer,
  }) = _Debt;
}

/// The rate charged on [debt] in [month] (1-based): the promotional rate
/// while it lasts, then [Debt.aprBps].
int aprInMonth(Debt debt, int month) => switch (debt.promo) {
  Promo(:final aprBps, :final months) when month <= months => aprBps,
  _ => debt.aprBps,
};
