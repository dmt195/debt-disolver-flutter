import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/src/money.dart';

part 'debt.freezed.dart';

enum DebtType { creditCard, loan, personal }

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
  }) = _Debt;
}
