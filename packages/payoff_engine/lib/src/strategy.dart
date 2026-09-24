import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/src/money.dart';

part 'strategy.freezed.dart';

enum StrategyId {
  avalanche,
  snowball,
  customOrder,
  consolidation,
  balanceTransfer,
  minimumsOnly,
}

@freezed
sealed class Strategy with _$Strategy {
  /// Extra money to the debt with the highest rate that month.
  const factory Strategy.avalanche() = Avalanche;

  /// Extra money to the smallest starting balance first.
  const factory Strategy.snowball() = Snowball;

  /// Extra money to the debts in the order they are listed.
  const factory Strategy.customOrder() = CustomOrder;

  /// Replace every consolidatable debt with one loan at [aprBps], repaid
  /// over [termMonths] months, plus a [feeBps] arrangement fee. What the
  /// budget has left over the loan payment goes to the loan and the other
  /// debts.
  const factory Strategy.consolidation({
    required int aprBps,
    @Default(60) int termMonths,
    @Default(0) int feeBps,
  }) = Consolidation;

  /// Move card balances that charge interest to a card at 0% for
  /// [promoMonths] months, then [revertAprBps], adding a [feeBps] fee. At
  /// most [creditLimit] (fees included) moves; with no limit, everything
  /// eligible fits.
  const factory Strategy.balanceTransfer({
    required int feeBps,
    required int promoMonths,
    required int revertAprBps,
    Money? creditLimit,
  }) = BalanceTransfer;

  /// Only the minimum on every debt: the baseline the others are compared
  /// with.
  const factory Strategy.minimumsOnly() = MinimumsOnly;

  const Strategy._();

  StrategyId get id => switch (this) {
    Avalanche() => StrategyId.avalanche,
    Snowball() => StrategyId.snowball,
    CustomOrder() => StrategyId.customOrder,
    Consolidation() => StrategyId.consolidation,
    BalanceTransfer() => StrategyId.balanceTransfer,
    MinimumsOnly() => StrategyId.minimumsOnly,
  };
}

/// Defaults are the legacy app's Settings-screen values (preferences.xml).
@freezed
abstract class StrategyParameters with _$StrategyParameters {
  const factory StrategyParameters({
    @Default(500) int consolidationAprBps,
    @Default(60) int consolidationTermMonths,
    @Default(0) int consolidationFeeBps,
    @Default(400) int transferFeeBps,
    @Default(12) int promoMonths,
    @Default(1500) int revertAprBps,

    /// The transfer card's limit, in the budget currency; null assumes
    /// every eligible balance fits.
    Money? transferCreditLimit,
  }) = _StrategyParameters;
}

/// The five strategies the app ranks, in display order. The baseline
/// ([Strategy.minimumsOnly]) is run separately by `calculateBaseline`.
List<Strategy> standardStrategies(StrategyParameters p) => [
  const Strategy.avalanche(),
  const Strategy.snowball(),
  const Strategy.customOrder(),
  Strategy.consolidation(
    aprBps: p.consolidationAprBps,
    termMonths: p.consolidationTermMonths,
    feeBps: p.consolidationFeeBps,
  ),
  Strategy.balanceTransfer(
    feeBps: p.transferFeeBps,
    promoMonths: p.promoMonths,
    revertAprBps: p.revertAprBps,
    creditLimit: p.transferCreditLimit,
  ),
];
