import 'package:freezed_annotation/freezed_annotation.dart';

part 'strategy.freezed.dart';

enum StrategyId {
  avalanche,
  lowestAprFirst,
  boosted,
  consolidation,
  balanceTransfer,
}

@freezed
sealed class Strategy with _$Strategy {
  /// Pay the highest-APR debt first.
  const factory Strategy.avalanche() = Avalanche;

  /// Pay the lowest-APR debt first.
  const factory Strategy.lowestAprFirst() = LowestAprFirst;

  /// Avalanche with the budget raised to [budgetPercent] percent.
  const factory Strategy.boosted({@Default(110) int budgetPercent}) = Boosted;

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

  const Strategy._();

  StrategyId get id => switch (this) {
    Avalanche() => StrategyId.avalanche,
    LowestAprFirst() => StrategyId.lowestAprFirst,
    Boosted() => StrategyId.boosted,
    Consolidation() => StrategyId.consolidation,
    BalanceTransfer() => StrategyId.balanceTransfer,
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

/// The five strategies compared by the app, in display order.
List<Strategy> standardStrategies(StrategyParameters p) => [
  const Strategy.avalanche(),
  const Strategy.lowestAprFirst(),
  const Strategy.boosted(),
  Strategy.consolidation(aprBps: p.consolidationAprBps),
  Strategy.balanceTransfer(
    feeBps: p.transferFeeBps,
    promoMonths: p.promoMonths,
    revertAprBps: p.revertAprBps,
  ),
];
