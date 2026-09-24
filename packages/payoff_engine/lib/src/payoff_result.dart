import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/strategy.dart';

part 'payoff_result.freezed.dart';

@freezed
sealed class PayoffResult with _$PayoffResult {
  const factory PayoffResult.feasible({
    required StrategyId strategyId,
    required PayoffPlan plan,
  }) = Feasible;

  /// The budget can't cover the minimum payments in [month] (1-based);
  /// it is [shortfall] short.
  const factory PayoffResult.infeasible({
    required StrategyId strategyId,
    required Money shortfall,
    required int month,
  }) = Infeasible;

  /// The debts are not cleared within [kMaxMonths] months.
  const factory PayoffResult.neverClears({required StrategyId strategyId}) =
      NeverClears;

  /// [strategyId] can't be used with these debts, for [reason].
  const factory PayoffResult.notApplicable({
    required StrategyId strategyId,
    required NotApplicableReason reason,
  }) = NotApplicable;
}

/// A debt as it appears in a plan: a column in every [MonthRow].
@freezed
abstract class PlanDebt with _$PlanDebt {
  const factory PlanDebt({
    required String id,
    required String name,
    required Money startingBalance,
  }) = _PlanDebt;
}

@freezed
abstract class MonthRow with _$MonthRow {
  /// Lists are indexed like [PayoffPlan.debts].
  const factory MonthRow({
    required int month,
    required List<Money> interest,
    required List<Money> payments,
    required List<Money> closingBalances,
  }) = _MonthRow;
}

@freezed
abstract class PayoffPlan with _$PayoffPlan {
  const factory PayoffPlan({
    /// In clearing order: the order the debts are paid off in.
    required List<PlanDebt> debts,
    required List<MonthRow> months,
    required Money totalPaid,
    required Money totalInterest,

    /// One-off fees, e.g. a balance-transfer fee.
    required Money totalFees,

    /// What the strategy moved or replaced, if anything.
    PlanChange? change,
  }) = _PayoffPlan;

  const PayoffPlan._();

  int get monthsToClear => months.length;

  List<String> get payoffOrder => [for (final d in debts) d.id];
}

/// Calculation stops after this many months (100 years).
const int kMaxMonths = 1200;

enum NotApplicableReason { noTransferableBalances, nothingToConsolidate }

/// A balance moved to a transfer card or replaced by a consolidation loan.
@freezed
abstract class MovedBalance with _$MovedBalance {
  const factory MovedBalance({
    required String debtId,
    required String name,
    required Money amount,
  }) = _MovedBalance;
}

/// What a strategy changed about the user's debts.
@freezed
sealed class PlanChange with _$PlanChange {
  /// [moved] went to a card at 0% for [promoMonths] months. [creditLimit]
  /// was assumed (just enough for everything) when [limitAssumed].
  const factory PlanChange.transfer({
    required List<MovedBalance> moved,
    required Money fee,
    required Money creditLimit,
    required bool limitAssumed,
    required int promoMonths,
  }) = TransferChange;
}
