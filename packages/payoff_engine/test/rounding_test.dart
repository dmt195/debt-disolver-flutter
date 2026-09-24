import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

void main() {
  group('divideHalfEven', () {
    test('divides exactly when there is no remainder', () {
      expect(divideHalfEven(100, 4), 25);
    });

    test('rounds down below half and up above half', () {
      expect(divideHalfEven(14, 10), 1);
      expect(divideHalfEven(16, 10), 2);
    });

    test('rounds exact halves to the even neighbour', () {
      expect(divideHalfEven(15, 10), 2);
      expect(divideHalfEven(25, 10), 2);
      expect(divideHalfEven(35, 10), 4);
    });

    test('rejects a negative numerator or non-positive denominator', () {
      expect(() => divideHalfEven(-1, 10), throwsArgumentError);
      expect(() => divideHalfEven(1, 0), throwsArgumentError);
    });
  });
}
