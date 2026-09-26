import 'package:payoff_engine/src/interest.dart';
import 'package:payoff_engine/src/loan.dart';

/// The smallest whole monthly payment that clears [balanceMinor] at
/// [aprBps] within [termMonths] months, using the calculator's own monthly
/// interest and rounding (so the loan really does clear on time). Integer
/// arithmetic throughout: a binary search, not an annuity formula. A
/// balance that grows past the engine's ceiling during the search means
/// that trial payment can't clear, which keeps every product inside 64-bit
/// integers.
int fixedLoanPayment({
  required int balanceMinor,
  required int aprBps,
  required int termMonths,
}) => smallestClearingPayment(
  balanceMinor,
  aprBps,
  termMonths,
  monthlyInterest(),
);
