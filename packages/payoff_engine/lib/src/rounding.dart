/// Divides [numerator] by [denominator], rounding half to even.
///
/// Both arguments must be non-negative and [denominator] must be positive.
int divideHalfEven(int numerator, int denominator) {
  if (numerator < 0) {
    throw ArgumentError.value(numerator, 'numerator', 'must be >= 0');
  }
  if (denominator <= 0) {
    throw ArgumentError.value(denominator, 'denominator', 'must be > 0');
  }
  final quotient = numerator ~/ denominator;
  final twiceRemainder = (numerator % denominator) * 2;
  if (twiceRemainder > denominator) return quotient + 1;
  if (twiceRemainder == denominator && quotient.isOdd) return quotient + 1;
  return quotient;
}
