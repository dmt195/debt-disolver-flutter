import 'package:freezed_annotation/freezed_annotation.dart';

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

  /// Replace all debts with one loan at [aprBps]; the whole budget is the
  /// fixed monthly payment.
  const factory Strategy.consolidation({required int aprBps}) = Consolidation;

  /// Move all debts to a 0% card, adding a [feeBps] transfer fee. Interest at
  /// [revertAprBps] starts in month `promoMonths + 1`.
  const factory Strategy.balanceTransfer({
    required int feeBps,
    required int promoMonths,
    required int revertAprBps,
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
    @Default(400) int transferFeeBps,
    @Default(12) int promoMonths,
    @Default(1500) int revertAprBps,
  }) = _StrategyParameters;
}

/// The five strategies the app ranks, in display order. The baseline
/// ([Strategy.minimumsOnly]) is run separately by `calculateBaseline`.
List<Strategy> standardStrategies(StrategyParameters p) => [
  const Strategy.avalanche(),
  const Strategy.snowball(),
  const Strategy.customOrder(),
  Strategy.consolidation(aprBps: p.consolidationAprBps),
  Strategy.balanceTransfer(
    feeBps: p.transferFeeBps,
    promoMonths: p.promoMonths,
    revertAprBps: p.revertAprBps,
  ),
];
