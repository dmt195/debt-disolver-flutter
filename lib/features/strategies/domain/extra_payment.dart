import 'package:debt_destroyer/core/currency.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// A round slider step (1, 2 or 5 × 10ⁿ major units, never less than one)
/// that splits [budget] into about 60 steps, in minor units.
int extraPaymentStepMinor(Money budget) {
  final unit = rescaleMinor(
    1,
    fromDigits: 0,
    toDigits: currencyDecimalDigits(budget.currency),
  );
  final target = budget.minor ~/ unit ~/ 60;
  for (var magnitude = 1; ; magnitude *= 10) {
    for (final multiple in const [1, 2, 5]) {
      if (multiple * magnitude >= target) return multiple * magnitude * unit;
    }
  }
}

/// The pay-more extra actually applied on top of [budget]: [storedExtra]
/// clamped to whole slider steps (see [extraPaymentStepMinor]) within
/// [budget], and never negative. The one clamp every user of the stored
/// extra should apply, so they never disagree after the budget changes.
int effectiveExtraMinor(int storedExtra, Money budget) {
  final step = extraPaymentStepMinor(budget);
  final max = (budget.minor ~/ step) * step;
  return storedExtra.clamp(0, max);
}
